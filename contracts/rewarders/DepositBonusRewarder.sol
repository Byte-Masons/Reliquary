// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "./SingleAssetRewarder.sol";
import {IReliquary} from "../interfaces/IReliquary.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Extension of SingleAssetRewarder contract that distributes a bonus for deposits of a minimum size made on a
/// regular cadence.
contract DepositBonusRewarder is SingleAssetRewarder {
    using SafeERC20 for IERC20;

    uint256 public immutable depositBonus;
    uint256 public immutable minimum;
    uint256 public immutable cadence;

    /// @notice Mapping from relicId to timestamp of last deposit.
    mapping(uint256 => uint256) public lastDepositTime;

    /**
     * @dev Contructor called on deployment of this contract.
     * @param _depositBonus Bonus owed when cadence has elapsed since lastDepositTime.
     * @param _minimum The minimum deposit amount to be eligible for depositBonus.
     * @param _cadence The minimum elapsed time since lastDepositTime.
     * @param _rewardToken Address of token rewards are distributed in.
     * @param _reliquary Address of Reliquary this rewarder will read state from.
     */
    constructor(
        uint256 _depositBonus,
        uint256 _minimum,
        uint256 _cadence,
        address _rewardToken,
        address _reliquary
    ) SingleAssetRewarder(_rewardToken, _reliquary) {
        require(_minimum != 0, "no minimum set!");
        require(_cadence >= 1 days, "please set a reasonable cadence");
        depositBonus = _depositBonus;
        minimum = _minimum;
        cadence = _cadence;
    }

    /// @inheritdoc SingleAssetRewarder
    function onDeposit(uint256 _relicId, uint256 _depositAmount) external override onlyReliquary {
        if (_depositAmount >= minimum) {
            uint256 lastDepositTime_ = lastDepositTime[_relicId];
            uint256 timestamp_ = block.timestamp;
            lastDepositTime[_relicId] = timestamp_;
            _claimDepositBonus(
                IReliquary(reliquary).ownerOf(_relicId),
                timestamp_,
                lastDepositTime_
            );
        }
    }

    /// @inheritdoc SingleAssetRewarder
    function onWithdraw(
        uint256 _relicId,
        uint256 //_withdrawalAmount
    ) external override onlyReliquary {
        uint256 lastDepositTime_ = lastDepositTime[_relicId];
        delete lastDepositTime[_relicId];
        _claimDepositBonus(
            IReliquary(reliquary).ownerOf(_relicId),
            block.timestamp,
            lastDepositTime_
        );
    }

    /**
     * @notice Claim depositBonus without making another deposit.
     * @param _relicId The NFT ID of the position.
     * @param _to Address to send the depositBonus to.
     */
    function claimDepositBonus(uint256 _relicId, address _to) external {
        require(
            IReliquary(reliquary).isApprovedOrOwner(msg.sender, _relicId),
            "not owner or approved"
        );
        uint256 lastDepositTime_ = lastDepositTime[_relicId];
        delete lastDepositTime[_relicId];
        require(_claimDepositBonus(_to, block.timestamp, lastDepositTime_), "nothing to claim");
    }

    /// @inheritdoc SingleAssetRewarder
    function pendingToken(
        uint256 _relicId,
        uint256 //_rewardAmount
    ) public view override returns (uint256 pending) {
        uint256 lastDepositTime_ = lastDepositTime[_relicId];
        if (lastDepositTime_ != 0 && block.timestamp - lastDepositTime_ >= cadence) {
            pending += depositBonus;
        }
    }

    /**
     * @dev Internal claimDepositBonus function.
     * @param _to Address to send the depositBonus to.
     * @param _timestamp The current timestamp, passed in for gas efficiency.
     * @param _lastDepositTime Time of last deposit into this position, before being updated.
     * @return claimed_ Whether depositBonus was actually claimed.
     */
    function _claimDepositBonus(
        address _to,
        uint256 _timestamp,
        uint256 _lastDepositTime
    ) internal returns (bool claimed_) {
        if (_lastDepositTime != 0 && _timestamp - _lastDepositTime >= cadence) {
            IERC20(rewardToken).safeTransfer(_to, depositBonus);
            claimed_ = true;
        } else {
            claimed_ = false;
        }
    }
}
