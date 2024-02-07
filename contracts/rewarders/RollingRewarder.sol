// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "../interfaces/IRollingRewarder.sol";
import "./ChildRewarder.sol";
import "./SingleAssetRewarder.sol";
import {IReliquary, LevelInfo} from "../interfaces/IReliquary.sol";
import {IEmissionCurve} from "../interfaces/IEmissionCurve.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title Rewarder that can be funded with a set token, distributing it over a period of time.
contract RollingRewarder is IRollingRewarder, SingleAssetRewarder, ChildRewarder, Ownable {
    using SafeERC20 for IERC20;

    uint256 public immutable ACC_REWARD_PRECISION = 1e18;
    uint256 public immutable REWARD_PER_SECOND_PRECISION = 10_000;

    uint256 public immutable poolId;
    address public rewardsPool;

    uint256 public lastDistributionTime;
    uint256 public distributionPeriod;
    uint256 public lastIssuanceTimestamp;
    uint256 public totalIssued;

    uint256 public _rewardPerSecond;
    uint256 public accRewardPerShare;
    uint[] private multipliers;

    mapping(uint256 => uint256) public rewardDebt;
    mapping(uint256 => uint256) public rewardCredit;

    event LogOnReward(uint relicId, uint rewardAmount, address to);
    event UpdateDistributionPeriod(uint256 newDistributionPeriod);

    /**
     * @dev Contructor called on deployment of this contract.
     * @param _rewardToken Address of token rewards are distributed in.
     * @param _reliquary Address of Reliquary this rewarder will read state from.
     */
    constructor(
        address _rewardToken,
        address _reliquary,
        uint256 _poolId
    ) SingleAssetRewarder(_rewardToken, _reliquary) {
        poolId = _poolId;

        multipliers = IReliquary(_reliquary).getLevelInfo(_poolId).multipliers;

        _updateDistributionPeriod(7 days);
    }

    /**
     * @notice Called by Reliquary harvest or withdrawAndHarvest function.
     * @param to Address to send rewards to.
     */
    function onReward(
        uint relicId,
        uint, // rewardAmount
        address to,
        uint amount,
        uint oldLevel,
        uint newLevel
    ) external virtual override(IRewarder, SingleAssetRewarder) onlyParent {
        uint256 oldAmountMultiplied = amount * multipliers[oldLevel];
        uint256 newAmountMultiplied = amount * multipliers[newLevel];

        _issueTokens(_poolBalance());

        uint256 pending = ((oldAmountMultiplied * accRewardPerShare) /
            ACC_REWARD_PRECISION) - rewardDebt[relicId];
        pending += rewardCredit[relicId];

        rewardCredit[relicId] = 0;

        rewardDebt[relicId] = ((newAmountMultiplied * accRewardPerShare) /
            ACC_REWARD_PRECISION);
        if (pending > 0) {
            IERC20(rewardToken).safeTransfer(to, pending);
            emit LogOnReward(relicId, pending, to);
        }
    }

    function onDeposit(
        uint relicId,
        uint depositAmount,
        uint oldAmount,
        uint oldLevel,
        uint newLevel
    ) external virtual override(IRewarder, SingleAssetRewarder) onlyParent {
        uint256 oldAmountMultiplied = oldAmount * multipliers[oldLevel];
        uint256 newAmountMultiplied = (oldAmount + depositAmount) *
            multipliers[newLevel];

        _issueTokens(_poolBalance());

        rewardCredit[relicId] +=
            ((oldAmountMultiplied * accRewardPerShare) / ACC_REWARD_PRECISION) -
            rewardDebt[relicId];
        rewardDebt[relicId] = ((newAmountMultiplied * accRewardPerShare) /
            ACC_REWARD_PRECISION);
    }

    function onWithdraw(
        uint relicId,
        uint withdrawalAmount,
        uint oldAmount,
        uint oldLevel,
        uint newLevel
    ) external virtual override(IRewarder, SingleAssetRewarder) onlyParent {
        uint256 oldAmountMultiplied = oldAmount * multipliers[oldLevel];
        uint256 newAmountMultiplied = (oldAmount - withdrawalAmount) *
            multipliers[newLevel];

        _issueTokens(_poolBalance());

        rewardCredit[relicId] +=
            (oldAmountMultiplied * accRewardPerShare) /
            ACC_REWARD_PRECISION -
            rewardDebt[relicId];
        rewardDebt[relicId] = ((newAmountMultiplied * accRewardPerShare) /
            ACC_REWARD_PRECISION);
    }

    function onSplit(
        uint fromId,
        uint newId,
        uint amount,
        uint fromAmount,
        uint level
    ) external virtual onlyParent {
        _issueTokens(_poolBalance());
        uint256 _multiplier = multipliers[level];
        rewardCredit[fromId] +=
            ((fromAmount * _multiplier * accRewardPerShare) /
                ACC_REWARD_PRECISION) -
            rewardDebt[fromId];
        rewardDebt[fromId] = (((fromAmount - amount) *
            _multiplier *
            accRewardPerShare) / ACC_REWARD_PRECISION);
        rewardDebt[newId] = ((amount * _multiplier * accRewardPerShare) /
            ACC_REWARD_PRECISION);
    }

    function onShift(
        uint fromId,
        uint toId,
        uint amount,
        uint oldFromAmount,
        uint oldToAmount,
        uint fromLevel,
        uint oldToLevel,
        uint newToLevel
    ) external virtual onlyParent {
        uint256 _multiplierFrom = multipliers[fromLevel];

        _issueTokens(_poolBalance());

        rewardCredit[fromId] +=
            ((oldFromAmount * _multiplierFrom * accRewardPerShare) /
                ACC_REWARD_PRECISION) -
            rewardDebt[fromId];
        rewardDebt[fromId] = (((oldFromAmount - amount) *
            _multiplierFrom *
            accRewardPerShare) / ACC_REWARD_PRECISION);
        rewardCredit[toId] +=
            ((oldToAmount * multipliers[oldToLevel] * accRewardPerShare) /
                ACC_REWARD_PRECISION) -
            rewardDebt[toId];
        rewardDebt[toId] = (((oldToAmount + amount) *
            multipliers[newToLevel] *
            accRewardPerShare) / ACC_REWARD_PRECISION);
    }

    function onMerge(
        uint fromId,
        uint toId,
        uint fromAmount,
        uint toAmount,
        uint fromLevel,
        uint oldToLevel,
        uint newToLevel
    ) external virtual onlyParent {
        uint fromAmountMultiplied = fromAmount * multipliers[fromLevel];
        uint oldToAmountMultiplied = toAmount * multipliers[oldToLevel];
        uint newToAmountMultiplied = (toAmount + fromAmount) *
            multipliers[newToLevel];

        _issueTokens(_poolBalance());

        uint pendingTo = (accRewardPerShare *
            (fromAmountMultiplied + oldToAmountMultiplied)) /
            ACC_REWARD_PRECISION +
            rewardCredit[fromId] -
            rewardDebt[fromId] -
            rewardDebt[toId];
        if (pendingTo != 0) {
            rewardCredit[toId] += pendingTo;
        }

        rewardCredit[fromId] = 0;

        rewardDebt[toId] =
            (newToAmountMultiplied * accRewardPerShare) /
            ACC_REWARD_PRECISION;
    }

    /// @notice Returns the amount of pending rewardToken for a position from this rewarder.
    /// @param rewardAmount Amount of reward token owed for this position from the Reliquary.
    function pendingTokens(
        uint, //relicId
        uint rewardAmount
    )
        external
        view
        override(IRewarder, SingleAssetRewarder)
        returns (address[] memory, uint[] memory)
    {}

    function _updateDistributionPeriod(
        uint256 _newDistributionPeriod
    ) internal {
        distributionPeriod = _newDistributionPeriod;
        emit UpdateDistributionPeriod(_newDistributionPeriod);
    }

    function updateDistributionPeriod(
        uint256 _newDistributionPeriod
    ) external onlyOwner {
        _updateDistributionPeriod(_newDistributionPeriod);
    }

    function rewardPerSecond() public view returns (uint256) {
        return _rewardPerSecond;
    }

    function getRewardAmount(uint seconds_) public view returns (uint256) {
        return ((_rewardPerSecond * seconds_) / REWARD_PER_SECOND_PRECISION);
    }

    function _fund(uint256 _amount) internal {
        require(_amount != 0, "cannot fund 0");

        uint256 _lastIssuanceTimestamp = lastIssuanceTimestamp; //last time token was distributed
        uint256 _lastDistributionTime = lastDistributionTime; //timestamp of the final distribution of tokens
        uint256 amount = _amount; //amount of tokens to add to the distribution
        if (_lastIssuanceTimestamp < _lastDistributionTime) {
            uint256 timeLeft = _lastDistributionTime - _lastIssuanceTimestamp; //time left until final distribution
            uint256 notIssued = getRewardAmount(timeLeft); //how many tokens are left to issue
            amount += notIssued; // add to the funding amount that hasnt been issued
        }

        uint256 _distributionPeriod = distributionPeriod; //how many days will we distribute these assets over
        _rewardPerSecond =
            (amount * REWARD_PER_SECOND_PRECISION) /
            _distributionPeriod; //how many tokens per second will be distributed
        lastDistributionTime = block.timestamp + _distributionPeriod; //when will the new final distribution be
        lastIssuanceTimestamp = block.timestamp; //when was the last time tokens were distributed -- now

        IERC20(rewardToken).safeTransferFrom(
            rewardsPool,
            address(this),
            _amount
        ); //transfer the tokens to the contract
    }

    /// @notice Issues tokens.
    /// @param poolBalance Amount of tokens in the pool. This must be passed because the pool balance may have changed.
    /// @return issuance Amount of tokens issued.
    function _issueTokens(
        uint256 poolBalance
    ) internal returns (uint256 issuance) {
        uint256 _lastIssuanceTimestamp = lastIssuanceTimestamp; //last time token was distributed
        uint256 _lastDistributionTime = lastDistributionTime; //timestamp of the final distribution of tokens
        uint256 _totalIssued = totalIssued; //how many tokens to issue
        if (_lastIssuanceTimestamp < _lastDistributionTime) {
            uint256 endTimestamp = block.timestamp > _lastDistributionTime
                ? _lastDistributionTime
                : block.timestamp;
            uint256 timePassed = endTimestamp - _lastIssuanceTimestamp;
            issuance = getRewardAmount(timePassed);
            if (poolBalance != 0) {
                accRewardPerShare +=
                    (issuance * ACC_REWARD_PRECISION) /
                    poolBalance;

                _totalIssued = _totalIssued + issuance;
                totalIssued = _totalIssued;
            }
        }

        lastIssuanceTimestamp = block.timestamp;
    }

    function _poolBalance() internal view returns (uint256 total) {
        LevelInfo memory levelInfo = IReliquary(reliquary).getLevelInfo(poolId);
        uint length = levelInfo.balance.length;
        for (uint i; i < length; ) {
            total += levelInfo.balance[i] * levelInfo.multipliers[i];
            unchecked {
                ++i;
            }
        }
    }

    function fund() external {
        require(msg.sender == rewardsPool, "only rewards pool can fund");
        _fund(IERC20(rewardToken).balanceOf(rewardsPool));
    }

    function setRewardsPool(address _rewardsPool) external {
        require(msg.sender == parent, "only parent can set rewards pool");
        rewardsPool = _rewardsPool;
    }
}
