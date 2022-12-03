// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "../interfaces/IRewarder.sol";
import "../interfaces/IReliquary.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract SingleAssetRewarder is IRewarder {
    IERC20 public immutable rewardToken;
    IReliquary public immutable reliquary;

    /// @dev Limits function calls to address of Reliquary contract `reliquary`
    modifier onlyReliquary() {
        require(msg.sender == address(reliquary), "Only Reliquary can call this function.");
        _;
    }

    /**
     * @dev Contructor called on deployment of this contract.
     * @param _rewardToken Address of token rewards are distributed in.
     * @param _reliquary Address of Reliquary this rewarder will read state from.
     */
    constructor(IERC20 _rewardToken, IReliquary _reliquary) {
        rewardToken = _rewardToken;
        reliquary = _reliquary;
    }

    /**
     * @notice Called by Reliquary harvest or withdrawAndHarvest function.
     * @param rewardAmount Amount of reward token owed for this position from the Reliquary.
     * @param to Address to send rewards to.
     */
    function onReward(uint relicId, uint rewardAmount, address to) external virtual override {}

    /// @notice Called by Reliquary _deposit function.
    function onDeposit(uint relicId, uint depositAmount) external virtual override {}

    /// @notice Called by Reliquary withdraw or withdrawAndHarvest function.
    function onWithdraw(uint relicId, uint withdrawalAmount) external virtual override {}

    /// @notice Returns the amount of pending rewardToken for a position from this rewarder.
    /// @param rewardAmount Amount of reward token owed for this position from the Reliquary.
    function pendingToken(uint relicId, uint rewardAmount) public view virtual returns (uint pending) {}

    /**
     * @notice Returns the amount of pending tokens for a position from this rewarder.
     * Interface supports multiple tokens.
     * @param rewardAmount Amount of reward token owed for this position from the Reliquary.
     */
    function pendingTokens(uint relicId, uint rewardAmount)
        external
        view
        virtual
        override
        returns (IERC20[] memory rewardTokens, uint[] memory rewardAmounts)
    {
        rewardTokens = new IERC20[](1);
        rewardTokens[0] = rewardToken;

        rewardAmounts = new uint[](1);
        rewardAmounts[0] = pendingToken(relicId, rewardAmount);
    }
}
