// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "./SingleAssetRewarder.sol";
import {IReliquary} from "../interfaces/IReliquary.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title Simple rewarder that distributes its own token based on a ratio to rewards emitted by the Reliquary
contract MultiplierRewarder is SingleAssetRewarder {
    using SafeERC20 for IERC20;

    uint public constant BASIS_POINTS = 1e18;
    uint public rewardMultiplier;

    event LogOnReward(uint indexed relicId, uint amount, address indexed to);

    /**
     * @dev Contructor called on deployment of this contract.
     * @param _rewardMultiplier Amount to multiply reward by, relative to BASIS_POINTS.
     * @param _rewardToken Address of token rewards are distributed in.
     * @param _reliquary Address of Reliquary this rewarder will read state from.
     */
    constructor(uint _rewardMultiplier, address _rewardToken, address _reliquary)
        SingleAssetRewarder(_rewardToken, _reliquary)
    {
        rewardMultiplier = _rewardMultiplier;
    }

    /**
     * @notice Called by Reliquary harvest or withdrawAndHarvest function.
     * @param rewardAmount Amount of reward token owed for this position from the Reliquary.
     * @param to Address to send rewards to.
     */
    function onReward(uint relicId, uint rewardAmount, address to) external virtual override onlyReliquary {
        _onReward(relicId, rewardAmount, to);
    }

    /// @dev Separate internal function that may be called by inheriting contracts.
    function _onReward(uint relicId, uint rewardAmount, address to) internal {
        if (rewardMultiplier != 0 && rewardAmount != 0) {
            IERC20(rewardToken).safeTransfer(to, pendingToken(relicId, rewardAmount));
        }
        emit LogOnReward(relicId, rewardAmount, to);
    }

    /// @notice Returns the amount of pending rewardToken for a position from this rewarder.
    /// @param rewardAmount Amount of reward token owed for this position from the Reliquary.
    function pendingToken(
        uint, //relicId
        uint rewardAmount
    ) public view override returns (uint pending) {
        pending = rewardAmount * rewardMultiplier / BASIS_POINTS;
    }
}
