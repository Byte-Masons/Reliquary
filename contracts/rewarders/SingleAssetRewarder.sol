// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "../interfaces/IRewarder.sol";
import "../interfaces/IReliquary.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// Simple rewarder that distributes its own token based on a ratio to rewards emitted by the Reliquary
contract SingleAssetRewarder is IRewarder {

    using SafeERC20 for IERC20;

    uint private immutable BASIS_POINTS;
    uint public rewardMultiplier;

    IERC20 public immutable rewardToken;
    IReliquary public immutable reliquary;

    modifier onlyReliquary() {
        require(msg.sender == address(reliquary), "Only Reliquary can call this function.");
        _;
    }

    event LogOnReward(uint indexed relicId, uint amount, address indexed to);

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
        BASIS_POINTS = 10 ** IERC20Metadata(address(_reliquary.rewardToken())).decimals();
    }

    /// @notice Called by Reliquary harvest or withdrawAndHarvest function
    /// @param rewardAmount Amount of reward token owed for this position from the Reliquary
    /// @param to Address to send rewards to
    function onReward(
        uint relicId,
        uint rewardAmount,
        address to
    ) external virtual override onlyReliquary {
        _onReward(relicId, rewardAmount, to);
    }

    function _onReward(
        uint relicId,
        uint rewardAmount,
        address to
    ) internal {
        if (rewardMultiplier != 0) {
            rewardToken.safeTransfer(to, pendingToken(rewardAmount));
        }
        emit LogOnReward(relicId, rewardAmount, to);
    }

    /// @notice Called by Reliquary _deposit function
    function onDeposit(
        uint, //relicId
        uint //depositAmount
    ) external virtual override {
    }

    /// @notice Called by Reliquary withdraw or withdrawAndHarvest function
    function onWithdraw(
        uint, //relicId
        uint //withdrawalAmount
    ) external virtual override {
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
