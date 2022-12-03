// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./MultiplierRewarder.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title Ownable extension of MultiplierRewarder that allows the owner to change the rewardMultiplier
contract MultiplierRewarderOwnable is MultiplierRewarder, Ownable {
    event LogRewardMultiplier(uint rewardMultiplier);

    /**
     * @dev Contructor called on deployment of this contract.
     * @param _rewardMultiplier Amount to multiply reward by, relative to BASIS_POINTS.
     * @param _rewardToken Address of token rewards are distributed in.
     * @param _reliquary Address of Reliquary this rewarder will read state from.
     */
    constructor(uint _rewardMultiplier, IERC20 _rewardToken, IReliquary _reliquary)
        MultiplierRewarder(_rewardMultiplier, _rewardToken, _reliquary)
    {}

    /// @notice Set a new rewardMultiplier. Only callable by `owner`.
    function setRewardMultiplier(uint _rewardMultiplier) external onlyOwner {
        rewardMultiplier = _rewardMultiplier;
        emit LogRewardMultiplier(_rewardMultiplier);
    }
}
