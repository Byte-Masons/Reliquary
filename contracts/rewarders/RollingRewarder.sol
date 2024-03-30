// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../interfaces/IRollingRewarder.sol";
import "../interfaces/IRewarder.sol";
import "../interfaces/IReliquary.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title Rewarder that can be funded with a set token, distributing it over a period of time.
contract RollingRewarder is IRollingRewarder {
    using SafeERC20 for IERC20;

    uint256 private constant REWARD_PER_SECOND_PRECISION = 10_000;

    address public immutable parent;
    address public immutable reliquary;
    address public immutable rewardToken;
    uint256 public immutable poolId;

    uint256 public lastDistributionTime;
    uint256 public distributionPeriod;
    uint256 public lastIssuanceTimestamp;
    uint256 public totalIssued;
    uint256 public totalRewardsSent;

    uint256 public rewardPerSecond;
    uint256 public accRewardPerShare;

    mapping(uint256 => uint256) private rewardDebt;
    mapping(uint256 => uint256) private rewardCredit;

    // Errors
    error RollingRewarder__NOT_PARENT();
    error RollingRewarder__NOT_OWNER();
    error RollingRewarder__ZERO_INPUT();

    // Events
    event LogOnReward(uint256 _relicId, uint256 _rewardAmount, address _to);
    event UpdateDistributionPeriod(uint256 _newDistributionPeriod);

    /// @dev We define owner of parent owner of the child too.
    modifier onlyOwner() {
        if (msg.sender != Ownable(parent).owner()) revert RollingRewarder__NOT_OWNER();
        _;
    }

    /// @dev Limits function calls to address of parent contract `ParentRollingRewarder`
    modifier onlyParent() {
        if (msg.sender != parent) revert RollingRewarder__NOT_PARENT();
        _;
    }

    /**
     * @dev Contructor called on deployment of this contract.
     * @param _rewardToken Address of token rewards are distributed in.
     * @param _reliquary Address of Reliquary this rewarder will read state from.
     */
    constructor(address _rewardToken, address _reliquary, uint256 _poolId) {
        poolId = _poolId;
        parent = msg.sender;
        rewardToken = _rewardToken;
        reliquary = _reliquary;
        _updateDistributionPeriod(7 days);
    }

    // -------------- Admin --------------

    function fund(uint256 _amount) external onlyOwner {
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), _amount);
        totalRewardsSent += _amount;
        _fund(_amount);
    }

    function updateDistributionPeriod(uint256 _newDistributionPeriod) external onlyOwner {
        _updateDistributionPeriod(_newDistributionPeriod);
    }

    // -------------- Hooks --------------

    function onUpdate(
        ICurves _curve,
        uint256 _relicId,
        uint256 _amount,
        uint256 _oldLevel,
        uint256 _newLevel
    ) external virtual onlyParent {
        uint256 oldAmountMultiplied_ = _amount * _curve.getFunction(_oldLevel);
        uint256 newAmountMultiplied_ = _amount * _curve.getFunction(_newLevel);

        _issueTokens();

        uint256 accRewardPerShare_ = accRewardPerShare;
        rewardCredit[_relicId] += Math.mulDiv(
            oldAmountMultiplied_, accRewardPerShare_, ACC_REWARD_PRECISION
        ) - rewardDebt[_relicId];
        rewardDebt[_relicId] =
            Math.mulDiv(newAmountMultiplied_, accRewardPerShare_, ACC_REWARD_PRECISION);
    }

    function onReward(
        ICurves _curve,
        uint256 _relicId,
        address _to,
        uint256 _amount,
        uint256 _oldLevel,
        uint256 _newLevel
    ) external virtual onlyParent {
        uint256 oldAmountMultiplied_ = _amount * _curve.getFunction(_oldLevel);
        uint256 newAmountMultiplied_ = _amount * _curve.getFunction(_newLevel);

        _issueTokens();

        uint256 accRewardPerShare_ = accRewardPerShare;
        uint256 pending_ = Math.mulDiv(
            oldAmountMultiplied_, accRewardPerShare_, ACC_REWARD_PRECISION
        ) - rewardDebt[_relicId];
        pending_ += rewardCredit[_relicId];

        rewardCredit[_relicId] = 0;

        rewardDebt[_relicId] =
            Math.mulDiv(newAmountMultiplied_, accRewardPerShare_, ACC_REWARD_PRECISION);

        if (pending_ > 0) {
            IERC20(rewardToken).safeTransfer(_to, pending_);
            emit LogOnReward(_relicId, pending_, _to);
        }
    }

    function onDeposit(
        ICurves _curve,
        uint256 _relicId,
        uint256 _depositAmount,
        uint256 _oldAmount,
        uint256 _oldLevel,
        uint256 _newLevel
    ) external virtual onlyParent {
        uint256 oldAmountMultiplied_ = _oldAmount * _curve.getFunction(_oldLevel);
        uint256 newAmountMultiplied_ = (_oldAmount + _depositAmount) * _curve.getFunction(_newLevel);

        _issueTokens();

        uint256 accRewardPerShare_ = accRewardPerShare;
        rewardCredit[_relicId] += Math.mulDiv(
            oldAmountMultiplied_, accRewardPerShare_, ACC_REWARD_PRECISION
        ) - rewardDebt[_relicId];
        rewardDebt[_relicId] =
            Math.mulDiv(newAmountMultiplied_, accRewardPerShare_, ACC_REWARD_PRECISION);
    }

    function onWithdraw(
        ICurves _curve,
        uint256 _relicId,
        uint256 _withdrawalAmount,
        uint256 _oldAmount,
        uint256 _oldLevel,
        uint256 _newLevel
    ) external virtual onlyParent {
        uint256 oldAmountMultiplied_ = _oldAmount * _curve.getFunction(_oldLevel);
        uint256 newAmountMultiplied_ =
            (_oldAmount - _withdrawalAmount) * _curve.getFunction(_newLevel);

        _issueTokens();

        uint256 accRewardPerShare_ = accRewardPerShare;
        rewardCredit[_relicId] += Math.mulDiv(
            oldAmountMultiplied_, accRewardPerShare_, ACC_REWARD_PRECISION
        ) - rewardDebt[_relicId];
        rewardDebt[_relicId] =
            Math.mulDiv(newAmountMultiplied_, accRewardPerShare_, ACC_REWARD_PRECISION);
    }

    function onSplit(
        ICurves _curve,
        uint256 _fromId,
        uint256 _newId,
        uint256 _amount,
        uint256 _fromAmount,
        uint256 _level
    ) external virtual onlyParent {
        _issueTokens();

        uint256 accRewardPerShare_ = accRewardPerShare;
        uint256 multiplier_ = _curve.getFunction(_level);
        rewardCredit[_fromId] += Math.mulDiv(
            _fromAmount, multiplier_ * accRewardPerShare_, ACC_REWARD_PRECISION
        ) - rewardDebt[_fromId];
        rewardDebt[_fromId] = Math.mulDiv(
            _fromAmount - _amount, multiplier_ * accRewardPerShare_, ACC_REWARD_PRECISION
        );
        rewardDebt[_newId] =
            Math.mulDiv(_amount, multiplier_ * accRewardPerShare_, ACC_REWARD_PRECISION);
    }

    function onShift(
        ICurves _curve,
        uint256 _fromId,
        uint256 _toId,
        uint256 _amount,
        uint256 _oldFromAmount,
        uint256 _oldToAmount,
        uint256 _fromLevel,
        uint256 _oldToLevel,
        uint256 _newToLevel
    ) external virtual onlyParent {
        uint256 _multiplierFrom = _curve.getFunction(_fromLevel);

        _issueTokens();

        uint256 accRewardPerShare_ = accRewardPerShare;
        rewardCredit[_fromId] += Math.mulDiv(
            _oldFromAmount, _multiplierFrom * accRewardPerShare_, ACC_REWARD_PRECISION
        ) - rewardDebt[_fromId];
        rewardDebt[_fromId] = Math.mulDiv(
            _oldFromAmount - _amount, _multiplierFrom * accRewardPerShare_, ACC_REWARD_PRECISION
        );
        rewardCredit[_toId] += Math.mulDiv(
            _oldToAmount, _curve.getFunction(_oldToLevel) * accRewardPerShare_, ACC_REWARD_PRECISION
        ) - rewardDebt[_toId];
        rewardDebt[_toId] = Math.mulDiv(
            _oldToAmount + _amount,
            _curve.getFunction(_newToLevel) * accRewardPerShare_,
            ACC_REWARD_PRECISION
        );
    }

    function onMerge(
        ICurves _curve,
        uint256 _fromId,
        uint256 _toId,
        uint256 _fromAmount,
        uint256 _toAmount,
        uint256 _fromLevel,
        uint256 _oldToLevel,
        uint256 _newToLevel
    ) external virtual onlyParent {
        uint256 fromAmountMultiplied_ = _fromAmount * _curve.getFunction(_fromLevel);
        uint256 oldToAmountMultiplied_ = _toAmount * _curve.getFunction(_oldToLevel);
        uint256 newToAmountMultiplied_ = (_toAmount + _fromAmount) * _curve.getFunction(_newToLevel);

        _issueTokens();

        uint256 accRewardPerShare_ = accRewardPerShare;
        uint256 pendingTo_ = Math.mulDiv(
            accRewardPerShare_, fromAmountMultiplied_ + oldToAmountMultiplied_, ACC_REWARD_PRECISION
        ) + rewardCredit[_fromId] - rewardDebt[_fromId] - rewardDebt[_toId];
        if (pendingTo_ != 0) {
            rewardCredit[_toId] += pendingTo_;
        }

        rewardCredit[_fromId] = 0;

        rewardDebt[_toId] =
            Math.mulDiv(newToAmountMultiplied_, accRewardPerShare_, ACC_REWARD_PRECISION);
    }

    // -------------- Internals --------------

    function _updateDistributionPeriod(uint256 _newDistributionPeriod) internal {
        distributionPeriod = _newDistributionPeriod;
        emit UpdateDistributionPeriod(_newDistributionPeriod);
    }

    function _fund(uint256 _amount) internal {
        if (_amount == 0) revert RollingRewarder__ZERO_INPUT();

        uint256 lastIssuanceTimestamp_ = lastIssuanceTimestamp; // Last time token was distributed.
        uint256 lastDistributionTime_ = lastDistributionTime; // Timestamp of the final distribution of tokens.
        uint256 amount_ = _amount; // Amount of tokens to add to the distribution.

        if (lastIssuanceTimestamp_ < lastDistributionTime_) {
            amount_ += getRewardAmount(lastDistributionTime_ - lastIssuanceTimestamp_); // Add to the funding amount that hasnt been issued.
        }

        uint256 distributionPeriod_ = distributionPeriod; // How many days will we distribute these assets over.
        rewardPerSecond = (amount_ * REWARD_PER_SECOND_PRECISION) / distributionPeriod_; // How many tokens per second will be distributed.
        lastDistributionTime = block.timestamp + distributionPeriod_; // When will the new final distribution be.
        lastIssuanceTimestamp = block.timestamp; // When was the last time tokens were distributed -- now.
    }

    function _issueTokens() internal returns (uint256 issuance_) {
        uint256 poolBalance_ = IReliquary(reliquary).getPoolInfo(poolId).totalLpSupplied;
        uint256 lastIssuanceTimestamp_ = lastIssuanceTimestamp; // Last time token was distributed.
        uint256 lastDistributionTime_ = lastDistributionTime; // Timestamp of the final distribution of tokens.

        if (lastIssuanceTimestamp_ < lastDistributionTime_) {
            uint256 endTimestamp_ =
                block.timestamp > lastDistributionTime_ ? lastDistributionTime_ : block.timestamp;
            issuance_ = getRewardAmount(endTimestamp_ - lastIssuanceTimestamp_);
            if (poolBalance_ != 0) {
                accRewardPerShare += Math.mulDiv(issuance_, ACC_REWARD_PRECISION, poolBalance_);

                totalIssued = totalIssued + issuance_;
            }
        }
        lastIssuanceTimestamp = block.timestamp;
    }

    // -------------- View --------------

    /// @notice Returns the amount of pending rewardToken for a position from this rewarder.
    function pendingToken(uint256 _relicId) public view returns (uint256 amount_) {
        uint256 poolBalance_ = IReliquary(reliquary).getPoolInfo(poolId).totalLpSupplied;
        uint256 lastIssuanceTimestamp_ = lastIssuanceTimestamp; // Last time token was distributed.
        uint256 lastDistributionTime_ = lastDistributionTime; // Timestamp of the final distribution of tokens.
        uint256 newAccReward_ = accRewardPerShare;
        if (lastIssuanceTimestamp_ < lastDistributionTime_) {
            uint256 endTimestamp_ =
                block.timestamp > lastDistributionTime_ ? lastDistributionTime_ : block.timestamp;
            uint256 issuance_ = getRewardAmount(endTimestamp_ - lastIssuanceTimestamp_);
            if (poolBalance_ != 0) {
                newAccReward_ += Math.mulDiv(issuance_, ACC_REWARD_PRECISION, poolBalance_);
            }
        }

        PositionInfo memory position_ = IReliquary(reliquary).getPositionForId(_relicId);
        uint256 amountMultiplied_ = position_.amount
            * IReliquary(reliquary).getPoolInfo(poolId).curve.getFunction(position_.level);

        uint256 pending_ = Math.mulDiv(amountMultiplied_, newAccReward_, ACC_REWARD_PRECISION)
            - rewardDebt[_relicId];
        pending_ += rewardCredit[_relicId];

        amount_ = pending_;
    }

    function pendingTokens(uint256 _relicId)
        external
        view
        virtual
        override
        returns (address[] memory rewardTokens_, uint256[] memory rewardAmounts_)
    {
        rewardTokens_ = new address[](1);
        rewardTokens_[0] = rewardToken;

        rewardAmounts_ = new uint256[](1);
        rewardAmounts_[0] = pendingToken(_relicId);
    }

    function getRewardAmount(uint256 _seconds) public view returns (uint256) {
        return ((rewardPerSecond * _seconds) / REWARD_PER_SECOND_PRECISION);
    }
}
