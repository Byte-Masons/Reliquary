// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "./SingleAssetRewarder.sol";

/// @title Extension of SingleAssetRewarder contract that distributes a bonus for deposits of a minimum size made on a
/// regular cadence.
contract DepositBonusRewarder is SingleAssetRewarder {
    using SafeERC20 for IERC20;

    uint public immutable depositBonus;
    uint public immutable minimum;
    uint public immutable cadence;

    /// @notice Mapping from relicId to timestamp of last deposit.
    mapping(uint => uint) public lastDepositTime;

    /**
     * @dev Contructor called on deployment of this contract.
     * @param _depositBonus Bonus owed when cadence has elapsed since lastDepositTime.
     * @param _minimum The minimum deposit amount to be eligible for depositBonus.
     * @param _cadence The minimum elapsed time since lastDepositTime.
     * @param _rewardToken Address of token rewards are distributed in.
     * @param _reliquary Address of Reliquary this rewarder will read state from.
     */
    constructor(uint _depositBonus, uint _minimum, uint _cadence, IERC20 _rewardToken, IReliquary _reliquary)
        SingleAssetRewarder(_rewardToken, _reliquary)
    {
        require(_minimum != 0, "no minimum set!");
        require(_cadence >= 1 days, "please set a reasonable cadence");
        depositBonus = _depositBonus;
        minimum = _minimum;
        cadence = _cadence;
    }

    /// @inheritdoc SingleAssetRewarder
    function onDeposit(uint relicId, uint depositAmount) external override onlyReliquary {
        if (depositAmount >= minimum) {
            uint _lastDepositTime = lastDepositTime[relicId];
            uint timestamp = block.timestamp;
            lastDepositTime[relicId] = timestamp;
            _claimDepositBonus(reliquary.ownerOf(relicId), timestamp, _lastDepositTime);
        }
    }

    /// @inheritdoc SingleAssetRewarder
    function onWithdraw(
        uint relicId,
        uint //withdrawalAmount
    ) external override onlyReliquary {
        uint _lastDepositTime = lastDepositTime[relicId];
        delete lastDepositTime[relicId];
        _claimDepositBonus(reliquary.ownerOf(relicId), block.timestamp, _lastDepositTime);
    }

    /**
     * @notice Claim depositBonus without making another deposit.
     * @param relicId The NFT ID of the position.
     * @param to Address to send the depositBonus to.
     */
    function claimDepositBonus(uint relicId, address to) external {
        require(reliquary.isApprovedOrOwner(msg.sender, relicId), "not owner or approved");
        uint _lastDepositTime = lastDepositTime[relicId];
        delete lastDepositTime[relicId];
        require(_claimDepositBonus(to, block.timestamp, _lastDepositTime), "nothing to claim");
    }

    /**
     * @dev Internal claimDepositBonus function.
     * @param to Address to send the depositBonus to.
     * @param timestamp The current timestamp, passed in for gas efficiency.
     * @param _lastDepositTime Time of last deposit into this position, before being updated.
     * @return claimed Whether depositBonus was actually claimed.
     */
    function _claimDepositBonus(address to, uint timestamp, uint _lastDepositTime) internal returns (bool claimed) {
        if (_lastDepositTime != 0 && timestamp - _lastDepositTime >= cadence) {
            rewardToken.safeTransfer(to, depositBonus);
            claimed = true;
        } else {
            claimed = false;
        }
    }

    /// @inheritdoc SingleAssetRewarder
    function pendingToken(
        uint relicId,
        uint //rewardAmount
    ) public view override returns (uint pending) {
        uint _lastDepositTime = lastDepositTime[relicId];
        if (_lastDepositTime != 0 && block.timestamp - _lastDepositTime >= cadence) {
            pending += depositBonus;
        }
    }
}
