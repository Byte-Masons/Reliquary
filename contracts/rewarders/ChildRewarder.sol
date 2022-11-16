// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./SingleAssetRewarderOwnable.sol";

/// Child rewarder contract to be deployed and called by a ParentRewarder, rather than directly by the Reliquary
contract ChildRewarder is SingleAssetRewarderOwnable {

    address public immutable parent;

    modifier onlyParent() {
        require(msg.sender == address(parent), "Only parent can call this function.");
        _;
    }

    /// @notice Contructor called on deployment of this contract
    /// @param _rewardMultiplier Amount to multiply reward by, relative to BASIS_POINTS
    /// @param _rewardToken Address of token rewards are distributed in
    /// @param _reliquary Address of Reliquary this rewarder will read state from
    constructor(
        uint _rewardMultiplier,
        IERC20 _rewardToken,
        IReliquary _reliquary
    ) SingleAssetRewarderOwnable(_rewardMultiplier, _rewardToken, _reliquary) {
        parent = msg.sender;
    }

    /// @notice Called by Reliquary harvest or withdrawAndHarvest function
    /// @param rewardAmount Amount of reward token owed for this position from the Reliquary
    /// @param to Address to send rewards to
    function onReward(
        uint, //relicId
        uint rewardAmount,
        address to
    ) external override onlyParent {
        super._onReward(0, rewardAmount, to);
    }
}
