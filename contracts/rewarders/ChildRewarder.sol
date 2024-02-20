// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./MultiplierRewarderOwnable.sol";

/// @title Child rewarder contract to be deployed and called by a ParentRewarder, rather than directly by the Reliquary.
contract ChildRewarder is MultiplierRewarderOwnable {
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
    constructor(uint256 _rewardMultiplier, address _rewardToken, address _reliquary)
        MultiplierRewarderOwnable(_rewardMultiplier, _rewardToken, _reliquary)
    {
        parent = msg.sender;
    }

    /// @inheritdoc SingleAssetRewarder
    function onReward(uint256 _relicId, uint256 _rewardAmount, address _to) external override onlyParent {
        super._onReward(_relicId, _rewardAmount, _to);
    }
}
