// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "../interfaces/IRewarder.sol";
import "../interfaces/IReliquary.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract SingleAssetRewarder is IRewarder {

    using SafeERC20 for IERC20;

    uint private constant BASIS_POINTS = 10_000;
    uint public immutable rewardMultiplier;

    IERC20 public immutable rewardToken;
    IReliquary public immutable reliquary;

    modifier onlyReliquary() {
        require(msg.sender == address(reliquary), "Only Reliquary can call this function.");
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
    ) {
        rewardMultiplier = _rewardMultiplier;
        rewardToken = _rewardToken;
        reliquary = _reliquary;
    }

    /// @notice Called by Reliquary harvest or withdrawAndHarvest function
    /// @param rewardAmount Amount of reward token owed for this position from the Reliquary
    /// @param to Address to send rewards to
    function onReward(
        uint, //relicId
        uint rewardAmount,
        address to
    ) external override onlyReliquary {
        if (rewardMultiplier != 0) {
            rewardToken.safeTransfer(to, pendingToken(rewardAmount));
        }
    }

    /// @notice Called by Reliquary _deposit function
    function onDeposit(
        uint, //relicId
        uint //depositAmount
    ) external virtual override onlyReliquary {
    }

    /// @notice Called by Reliquary withdraw or withdrawAndHarvest function
    function onWithdraw(
        uint, //relicId
        uint //withdrawalAmount
    ) external virtual override onlyReliquary {
    }

    /// @notice Returns the amount of pending rewardToken for a position from this rewarder
    /// @param rewardAmount Amount of reward token owed for this position from the Reliquary
    function pendingToken(uint rewardAmount) public view returns (uint pending) {
        pending = rewardAmount * rewardMultiplier / BASIS_POINTS;
    }

    /// @notice Returns the amount of pending tokens for a position from this rewarder
    ///         Interface supports multiple tokens
    /// @param rewardAmount Amount of reward token owed for this position from the Reliquary
    function pendingTokens(
        uint, //relicId
        uint rewardAmount
    ) external view virtual override returns (IERC20[] memory rewardTokens, uint[] memory rewardAmounts) {
        rewardTokens = new IERC20[](1);
        rewardTokens[0] = rewardToken;

        rewardAmounts = new uint[](1);
        rewardAmounts[0] = pendingToken(rewardAmount);
    }
}
