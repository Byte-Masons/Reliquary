// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./SingleAssetRewarder.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract SingleAssetRewarderOwnable is SingleAssetRewarder, Ownable {

    event LogRewardMultiplier(uint rewardMultiplier);

    /// @notice Contructor called on deployment of this contract
    /// @param _rewardMultiplier Amount to multiply reward by, relative to BASIS_POINTS
    /// @param _rewardToken Address of token rewards are distributed in
    /// @param _reliquary Address of Reliquary this rewarder will read state from
    constructor(
        uint _rewardMultiplier,
        IERC20 _rewardToken,
        IReliquary _reliquary
    ) SingleAssetRewarder(_rewardMultiplier, _rewardToken, _reliquary) {}

    function setRewardMultiplier(uint _rewardMultiplier) external onlyOwner {
        rewardMultiplier = _rewardMultiplier;
        emit LogRewardMultiplier(_rewardMultiplier);
    }
}
