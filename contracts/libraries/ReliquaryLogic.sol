// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "../interfaces/IReliquary.sol";
import "../interfaces/IRewarder.sol";
import "./ReliquaryEvents.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

library ReliquaryLogic {
    using SafeERC20 for IERC20;

    function _updateRelic(
        PositionInfo storage position,
        PoolInfo storage pool,
        Kind _kind,
        uint256 _amount,
        address _harvestTo,
        uint256 _accRewardPerShare,
        address _rewardToken
    )
        internal
        returns (
            uint256 received_,
            uint256 oldAmount_,
            uint256 newAmount_,
            uint256 oldLevel_,
            uint256 newLevel_
        )
    {
        oldAmount_ = position.amount;

        if (_kind == Kind.DEPOSIT) {
            _updateEntry(position, _amount);
            newAmount_ = oldAmount_ + _amount;
            position.amount = newAmount_;
        } else if (_kind == Kind.WITHDRAW) {
            if (_amount != oldAmount_ && !pool.allowPartialWithdrawals) {
                revert IReliquary.Reliquary__PARTIAL_WITHDRAWALS_DISABLED();
            }
            newAmount_ = oldAmount_ - _amount;
            position.amount = newAmount_;
        } else {
            /* Kind.HARVEST or Kind.UPDATE */
            newAmount_ = oldAmount_;
        }

        oldLevel_ = position.level;
        newLevel_ = _updateLevel(position, oldLevel_);

        position.rewardCredit += Math.mulDiv(
            oldAmount_, pool.curve.getFunction(oldLevel_) * _accRewardPerShare, ACC_REWARD_PRECISION
        ) - position.rewardDebt;
        position.rewardDebt = Math.mulDiv(
            newAmount_, pool.curve.getFunction(newLevel_) * _accRewardPerShare, ACC_REWARD_PRECISION
        );

        if (_kind == Kind.HARVEST) {
            received_ = _receivedReward(_rewardToken, position.rewardCredit);
            position.rewardCredit -= received_;
            if (received_ != 0) {
                IERC20(_rewardToken).safeTransfer(_harvestTo, received_);
            }
        }
    }

    function _updateRewarder(
        IRewarder _rewarder,
        ICurves _curve,
        Kind _kind,
        uint256 _relicId,
        uint256 _amount,
        address _harvestTo,
        uint256 _oldAmount,
        uint256 _oldLevel,
        uint256 _newLevel
    ) internal {
        if (_kind == Kind.DEPOSIT) {
            _rewarder.onDeposit(_curve, _relicId, _amount, _oldAmount, _oldLevel, _newLevel);
        } else if (_kind == Kind.WITHDRAW) {
            _rewarder.onWithdraw(_curve, _relicId, _amount, _oldAmount, _oldLevel, _newLevel);
        } else if (_kind == Kind.HARVEST) {
            _rewarder.onReward(_curve, _relicId, _harvestTo, _oldAmount, _oldLevel, _newLevel);
        } /* Kind.UPDATE */ else {
            _rewarder.onUpdate(_curve, _relicId, _oldAmount, _oldLevel, _newLevel);
        }
    }

    function _updateTotalLpSupplied(
        PoolInfo storage pool,
        Kind _kind,
        uint256 _amount,
        uint256 _oldAmount,
        uint256 _newAmount,
        uint256 _oldLevel,
        uint256 _newLevel
    ) internal {
        ICurves curve_ = pool.curve;

        if (_oldLevel != _newLevel) {
            pool.totalLpSupplied -= _oldAmount * curve_.getFunction(_oldLevel);
            pool.totalLpSupplied += _newAmount * curve_.getFunction(_newLevel);
        } else if (_kind == Kind.DEPOSIT) {
            pool.totalLpSupplied += _amount * curve_.getFunction(_oldLevel);
        } else if (_kind == Kind.WITHDRAW) {
            pool.totalLpSupplied -= _amount * curve_.getFunction(_oldLevel);
        }
    }

    /// @dev Internal `_updatePool` function without nonReentrant modifier.
    function _updatePool(PoolInfo storage pool, uint256 _emissionRate, uint256 _totalAllocPoint)
        internal
        returns (uint256 accRewardPerShare_)
    {
        uint256 timestamp_ = block.timestamp;
        uint256 lastRewardTime_ = pool.lastRewardTime;
        uint256 secondsSinceReward_ = timestamp_ - lastRewardTime_;

        accRewardPerShare_ = pool.accRewardPerShare;
        if (secondsSinceReward_ != 0) {
            uint256 lpSupply_ = pool.totalLpSupplied;

            if (lpSupply_ != 0) {
                uint256 reward_ =
                    (secondsSinceReward_ * _emissionRate * pool.allocPoint) / _totalAllocPoint;
                accRewardPerShare_ += Math.mulDiv(reward_, ACC_REWARD_PRECISION, lpSupply_);
                pool.accRewardPerShare = accRewardPerShare_;
            }

            pool.lastRewardTime = timestamp_;
        }
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending.
    function _massUpdatePools(
        PoolInfo[] storage poolInfo,
        uint256 _emissionRate,
        uint256 _totalAllocPoint
    ) internal {
        for (uint256 i_; i_ < poolInfo.length; ++i_) {
            _updatePool(poolInfo[i_], _emissionRate, _totalAllocPoint);
        }
    }

    /**
     * @notice Handle updating balances for each affected tranche when shifting and merging.
     * @param pool Pool `To` update.
     * @param _fromLevel `From` level.
     * @param _oldToLevel Old `To` level.
     * @param _newToLevel New `To level.
     * @param _amount The amount being transferred.
     * @param _toAmount Old `To` amount.
     * @param _newToAmount Old `To` amount plus `_amount`.
     */
    function _shiftLevelBalances(
        PoolInfo storage pool,
        uint256 _fromLevel,
        uint256 _oldToLevel,
        uint256 _newToLevel,
        uint256 _amount,
        uint256 _toAmount,
        uint256 _newToAmount
    ) internal {
        if (_fromLevel != _newToLevel) {
            pool.totalLpSupplied -= _amount * pool.curve.getFunction(_fromLevel);
        }
        if (_oldToLevel != _newToLevel) {
            pool.totalLpSupplied -= _toAmount * pool.curve.getFunction(_oldToLevel);
        }

        if (_fromLevel != _newToLevel && _oldToLevel != _newToLevel) {
            pool.totalLpSupplied += _newToAmount * pool.curve.getFunction(_newToLevel);
        } else if (_fromLevel != _newToLevel) {
            pool.totalLpSupplied += _amount * pool.curve.getFunction(_newToLevel);
        } else if (_oldToLevel != _newToLevel) {
            pool.totalLpSupplied += _toAmount * pool.curve.getFunction(_newToLevel);
        }
    }

    /**
     * @notice Used in `_updateEntry` to find weights without any underflows or zero division problems.
     * @param _addedValue New value being added.
     * @param _oldValue Current amount of x.
     */
    function _findWeight(uint256 _addedValue, uint256 _oldValue)
        internal
        pure
        returns (uint256 weightNew_)
    {
        if (_oldValue < _addedValue) {
            weightNew_ = 1e12 - (_oldValue * 1e12) / (_addedValue + _oldValue);
        } else if (_addedValue < _oldValue) {
            weightNew_ = (_addedValue * 1e12) / (_addedValue + _oldValue);
        } else {
            weightNew_ = 5e11;
        }
    }

    /**
     * @notice Updates the position's level based on entry time.
     * @param position The position being updated.
     * @param _oldLevel Level of position before update.
     * @return newLevel_ Level of position after update.
     */
    function _updateLevel(PositionInfo storage position, uint256 _oldLevel)
        internal
        returns (uint256 newLevel_)
    {
        newLevel_ = block.timestamp - position.entry;
        if (_oldLevel != newLevel_) {
            position.level = newLevel_;
        }
    }

    /**
     * @notice Calculate how much the owner will actually receive on harvest, given available reward tokens.
     * @param _pendingReward Amount of reward token owed.
     * @return received_ The minimum between amount owed and amount available.
     */
    function _receivedReward(address _rewardToken, uint256 _pendingReward)
        internal
        view
        returns (uint256 received_)
    {
        uint256 available_ = IERC20(_rewardToken).balanceOf(address(this));
        received_ = (available_ > _pendingReward) ? _pendingReward : available_;
    }

    /**
     * @notice Updates the user's entry time based on the weight of their deposit or withdrawal.
     * @param position The position being updated.
     * @param _amount The amount of the deposit / withdrawal.
     */
    function _updateEntry(PositionInfo storage position, uint256 _amount) internal {
        uint256 amountBefore_ = position.amount;
        if (amountBefore_ == 0) {
            position.entry = block.timestamp;
        } else {
            uint256 entryBefore_ = position.entry;
            uint256 maturity_ = block.timestamp - entryBefore_;
            position.entry = entryBefore_
                + (maturity_ * _findWeight(_amount, amountBefore_)) / 1e12;
        }
    }
}
