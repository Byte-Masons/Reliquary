// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../interfaces/IReliquary.sol";
import "../interfaces/IRewarder.sol";
import "./ReliquaryEvents.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

struct LocalVariables_updateRelic {
    uint256 received;
    uint256 oldAmount;
    uint256 newAmount;
    uint256 oldLevel;
    uint256 newLevel;
}

library ReliquaryLogic {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    // -------------- Internal --------------

    /**
     * @dev Update the position of a relic in a pool.
     * This function updates the position of a relic based on the provided kind (deposit, withdraw, harvest, or update),
     * calculates the reward credit and debt, and updates the total liquidity provider (LP) supplied for the pool.
     * @param position The PositionInfo structure representing the position of the relic to be updated.
     * @param pool The PoolInfo structure representing the pool containing the relic.
     * @param _kind The kind of update to be performed (deposit, withdraw, harvest, or update).
     * @param _relicId The ID of the relic.
     * @param _amount The amount of the relic to be deposited, withdrawn, or harvested.
     * @param _harvestTo The address to receive the harvested rewards.
     * @param _emissionRate The current emission rate.
     * @param _totalAllocPoint The total allocation points.
     * @param _rewardToken The address of the reward token.
     * @return The amount of rewards harvested.
     */
    function _updateRelic(
        PositionInfo storage position,
        PoolInfo storage pool,
        Kind _kind,
        uint256 _relicId,
        uint256 _amount,
        address _harvestTo,
        uint256 _emissionRate,
        uint256 _totalAllocPoint,
        address _rewardToken
    ) internal returns (uint256) {
        uint256 accRewardPerShare_ = _updatePool(pool, _emissionRate, _totalAllocPoint);

        LocalVariables_updateRelic memory vars_;
        vars_.oldAmount = uint256(position.amount);

        if (_kind == Kind.DEPOSIT) {
            _updateEntry(position, _amount);
            vars_.newAmount = vars_.oldAmount + _amount;
            position.amount = vars_.newAmount.toUint128();
        } else if (_kind == Kind.WITHDRAW) {
            if (_amount != vars_.oldAmount && !pool.allowPartialWithdrawals) {
                revert IReliquary.Reliquary__PARTIAL_WITHDRAWALS_DISABLED();
            }
            vars_.newAmount = vars_.oldAmount - _amount;
            position.amount = vars_.newAmount.toUint128();
        } else {
            /* Kind.HARVEST or Kind.UPDATE */
            vars_.newAmount = vars_.oldAmount;
        }

        vars_.oldLevel = uint256(position.level);
        vars_.newLevel = _updateLevel(position, vars_.oldLevel);

        position.rewardCredit += Math.mulDiv(
            vars_.oldAmount,
            pool.curve.getFunction(vars_.oldLevel) * accRewardPerShare_,
            ACC_REWARD_PRECISION
        ) - position.rewardDebt;
        position.rewardDebt = Math.mulDiv(
            vars_.newAmount,
            pool.curve.getFunction(vars_.newLevel) * accRewardPerShare_,
            ACC_REWARD_PRECISION
        );

        if (_harvestTo != address(0)) {
            vars_.received = _receivedReward(_rewardToken, position.rewardCredit);
            position.rewardCredit -= vars_.received;
            if (vars_.received != 0) {
                IERC20(_rewardToken).safeTransfer(_harvestTo, vars_.received);
            }
        }

        address rewarder_ = pool.rewarder;
        if (rewarder_ != address(0)) {
            _updateRewarder(
                IRewarder(rewarder_),
                pool.curve,
                _kind,
                _relicId,
                _amount,
                _harvestTo,
                vars_.oldAmount,
                vars_.oldLevel,
                vars_.newLevel
            );
        }

        _updateTotalLpSuppliedUpdateRelic(
            pool, _kind, _amount, vars_.oldAmount, vars_.newAmount, vars_.oldLevel, vars_.newLevel
        );

        return vars_.received;
    }

    /**
     * @dev Update the accumulated reward per share for a given pool.
     * This function calculates the amount of rewards that have been distributed since the last reward update,
     * and adds it to the accumulated reward per share.
     * @param pool The PoolInfo structure representing the pool to be updated.
     * @param _emissionRate The current emission rate.
     * @param _totalAllocPoint The total allocation points.
     * @return accRewardPerShare_ The updated accumulated reward per share.
     */
    function _updatePool(PoolInfo storage pool, uint256 _emissionRate, uint256 _totalAllocPoint)
        internal
        returns (uint256 accRewardPerShare_)
    {
        uint256 timestamp_ = block.timestamp;
        uint256 lastRewardTime_ = uint256(pool.lastRewardTime);
        uint256 secondsSinceReward_ = timestamp_ - lastRewardTime_;

        accRewardPerShare_ = pool.accRewardPerShare;
        if (secondsSinceReward_ != 0) {
            uint256 lpSupply_ = pool.totalLpSupplied;

            if (lpSupply_ != 0) {
                uint256 reward_ = (secondsSinceReward_ * _emissionRate * uint256(pool.allocPoint))
                    / _totalAllocPoint;
                accRewardPerShare_ += Math.mulDiv(reward_, ACC_REWARD_PRECISION, lpSupply_);
                pool.accRewardPerShare = accRewardPerShare_;
            }

            pool.lastRewardTime = uint40(timestamp_);
        }
    }

    /**
     * @dev Update reward variables for all pools in the `poolInfo` array.
     * This function iterates through the array and calls the `_updatePool` function for each pool.
     * Be mindful of gas costs when calling this function, as the gas cost increases with the number of pools.
     * @param poolInfo An array of PoolInfo structures representing the pools to be updated.
     * @param _emissionRate The current emission rate.
     * @param _totalAllocPoint The total allocation points of all pools.
     */
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
     * @dev Updates the total LP for each affected level when shifting or merging.
     * @param pool The pool for which the update is being made.
     * @param _fromLevel The level from which the transfer is happening.
     * @param _oldToLevel The old 'To' level.
     * @param _newToLevel The new 'To' level.
     * @param _amount The amount being transferred.
     * @param _toAmount The old 'To' amount.
     * @param _newToAmount The new 'To' amount, which is the sum of the old 'To' amount and the transferred amount.
     */
    function _updateTotalLpSuppliedShiftMerge(
        PoolInfo storage pool,
        uint256 _fromLevel,
        uint256 _oldToLevel,
        uint256 _newToLevel,
        uint256 _amount,
        uint256 _toAmount,
        uint256 _newToAmount
    ) internal {
        ICurves curve_ = pool.curve;

        if (_fromLevel != _newToLevel) {
            pool.totalLpSupplied -= _amount * curve_.getFunction(_fromLevel);
        }
        if (_oldToLevel != _newToLevel) {
            pool.totalLpSupplied -= _toAmount * curve_.getFunction(_oldToLevel);
        }

        if (_fromLevel != _newToLevel && _oldToLevel != _newToLevel) {
            pool.totalLpSupplied += _newToAmount * curve_.getFunction(_newToLevel);
        } else if (_fromLevel != _newToLevel) {
            pool.totalLpSupplied += _amount * curve_.getFunction(_newToLevel);
        } else if (_oldToLevel != _newToLevel) {
            pool.totalLpSupplied += _toAmount * curve_.getFunction(_newToLevel);
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
        newLevel_ = block.timestamp - uint256(position.entry);
        if (_oldLevel != newLevel_) {
            position.level = uint40(newLevel_);
        }
    }

    // -------------- Private --------------

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
    ) private {
        if (_kind == Kind.DEPOSIT) {
            _rewarder.onDeposit(_curve, _relicId, _amount, _oldAmount, _oldLevel, _newLevel);
        } else if (_kind == Kind.WITHDRAW) {
            _rewarder.onWithdraw(_curve, _relicId, _amount, _oldAmount, _oldLevel, _newLevel);
        } /* Kind.UPDATE */ else {
            _rewarder.onUpdate(_curve, _relicId, _oldAmount, _oldLevel, _newLevel);
        }

        if (_harvestTo != address(0)) {
            _rewarder.onReward(_relicId, _harvestTo);
        }
    }

    function _updateTotalLpSuppliedUpdateRelic(
        PoolInfo storage pool,
        Kind _kind,
        uint256 _amount,
        uint256 _oldAmount,
        uint256 _newAmount,
        uint256 _oldLevel,
        uint256 _newLevel
    ) private {
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

    /**
     * @notice Used in `_updateEntry` to find weights without any underflows or zero division problems.
     * @param _addedValue New value being added.
     * @param _oldValue Current amount of x.
     */
    function _findWeight(uint256 _addedValue, uint256 _oldValue)
        private
        pure
        returns (uint256 weightNew_)
    {
        if (_oldValue < _addedValue) {
            weightNew_ =
                WEIGHT_PRECISION - (_oldValue * WEIGHT_PRECISION) / (_addedValue + _oldValue);
        } else if (_addedValue < _oldValue) {
            weightNew_ = (_addedValue * WEIGHT_PRECISION) / (_addedValue + _oldValue);
        } else {
            weightNew_ = WEIGHT_PRECISION / 2;
        }
    }

    /**
     * @notice Updates the user's entry time based on the weight of their deposit or withdrawal.
     * @param position The position being updated.
     * @param _amount The amount of the deposit / withdrawal.
     */
    function _updateEntry(PositionInfo storage position, uint256 _amount) private {
        uint256 amountBefore_ = uint256(position.amount);
        if (amountBefore_ == 0) {
            position.entry = uint40(block.timestamp);
        } else {
            uint256 entryBefore_ = uint256(position.entry);
            uint256 maturity_ = block.timestamp - entryBefore_;
            position.entry = uint40(
                entryBefore_ + (maturity_ * _findWeight(_amount, amountBefore_)) / WEIGHT_PRECISION
            ); // unsafe cast ok
        }
    }

    /**
     * @notice Calculate how much the owner will actually receive on harvest, given available reward tokens.
     * @param _pendingReward Amount of reward token owed.
     * @return received_ The minimum between amount owed and amount available.
     */
    function _receivedReward(address _rewardToken, uint256 _pendingReward)
        private
        view
        returns (uint256 received_)
    {
        uint256 available_ = IERC20(_rewardToken).balanceOf(address(this));
        received_ = (available_ > _pendingReward) ? _pendingReward : available_;
    }
}
