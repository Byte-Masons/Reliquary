// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./SingleAssetRewarderOwnable.sol";

/// @title Child rewarder contract to be deployed and called by a ParentRewarder, rather than directly by the Reliquary.
contract ChildRewarder is SingleAssetRewarderOwnable {

    /// @notice Address of ParentRewarder which deployed this contract
    address public immutable parent;

    modifier onlyParent() {
        require(msg.sender == address(parent), "Only parent can call this function.");
        _;
    }

    /**
     * @dev Contructor called on deployment of this contract.
     * @param _rewardMultiplier Amount to multiply reward by, relative to BASIS_POINTS.
     * @param _rewardToken Address of token rewards are distributed in.
     * @param _reliquary Address of Reliquary this rewarder will read state from.
     */
    constructor(
        uint _rewardMultiplier,
        IERC20 _rewardToken,
        IReliquary _reliquary
    ) SingleAssetRewarderOwnable(_rewardMultiplier, _rewardToken, _reliquary) {
        parent = msg.sender;
    }

    /// @inheritdoc SingleAssetRewarder
    function onReward(
        uint relicId,
        uint rewardAmount,
        address to
    ) external override onlyParent {
        super._onReward(relicId, rewardAmount, to);
    }
}
