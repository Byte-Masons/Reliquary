// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "./SingleAssetRewarder.sol";
import {IReliquary} from "../interfaces/IReliquary.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title Simple rewarder that distributes its own token based on a ratio to rewards emitted by the Reliquary
contract MultiplierRewarder is SingleAssetRewarder {
    using SafeERC20 for IERC20;

    uint256 public constant BASIS_POINTS = 1e18;
    uint256 public rewardMultiplier;

    event LogOnReward(uint256 indexed relicId, uint256 amount, address indexed to);

    /**
     * @dev Contructor called on deployment of this contract.
     * @param _rewardMultiplier Amount to multiply reward by, relative to BASIS_POINTS.
     * @param _rewardToken Address of token rewards are distributed in.
     * @param _reliquary Address of Reliquary this rewarder will read state from.
     */
    constructor(
        uint256 _rewardMultiplier,
        address _rewardToken,
        address _reliquary
    ) SingleAssetRewarder(_rewardToken, _reliquary) {
        rewardMultiplier = _rewardMultiplier;
    }

    /**
     * @notice Called by Reliquary harvest or withdrawAndHarvest function.
     * @param _relicId The NFT ID of the position.
     * @param _rewardAmount Amount of reward token owed for this position from the Reliquary.
     * @param _to Address to send rewards to.
     */
    function onReward(
        uint256 _relicId,
        uint256 _rewardAmount,
        address _to
    ) external virtual override onlyReliquary {
        _onReward(_relicId, _rewardAmount, _to);
    }

    /// @dev Separate internal function that may be called by inheriting contracts.
    function _onReward(uint256 _relicId, uint256 _rewardAmount, address _to) internal {
        if (rewardMultiplier != 0 && _rewardAmount != 0) {
            IERC20(rewardToken).safeTransfer(_to, pendingToken(_relicId, _rewardAmount));
        }
        emit LogOnReward(_relicId, _rewardAmount, _to);
    }

    /// @notice Returns the amount of pending rewardToken for a position from this rewarder.
    /// @param _rewardAmount Amount of reward token owed for this position from the Reliquary.
    function pendingToken(
        uint256, //relicId
        uint256 _rewardAmount
    ) public view override returns (uint256 pending_) {
        pending_ = (_rewardAmount * rewardMultiplier) / BASIS_POINTS;
    }
}
