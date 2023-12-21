// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "../interfaces/IRewarder.sol";

abstract contract SingleAssetRewarder is IRewarder {
    address public rewardToken;
    address public immutable reliquary;

    /// @dev Limits function calls to address of Reliquary contract `reliquary`
    modifier onlyReliquary() {
        require(msg.sender == reliquary, "Only Reliquary can call this function.");
        _;
    }

    /**
     * @dev Contructor called on deployment of this contract.
     * @param _rewardToken Address of token rewards are distributed in.
     * @param _reliquary Address of Reliquary this rewarder will read state from.
     */
    constructor(address _rewardToken, address _reliquary) {
        rewardToken = _rewardToken;
        reliquary = _reliquary;
    }

    /**
     * @notice Called by Reliquary harvest or withdrawAndHarvest function.
     * @param rewardAmount Amount of reward token owed for this position from the Reliquary.
     * @param to Address to send rewards to.
     */
    function onReward(
        uint relicId,
        uint rewardAmount,
        address to,
        uint oldAmount,
        uint oldLevel,
        uint newLevel
    ) external virtual override {}
    
    /// @notice Called by Reliquary _deposit function.
    function onDeposit(
        uint relicId,
        uint depositAmount,
        uint oldAmount,
        uint oldLevel,
        uint newLevel
    ) external virtual override {}

    /// @notice Called by Reliquary withdraw or withdrawAndHarvest function.
    function onWithdraw(
        uint relicId,
        uint withdrawalAmount,
        uint oldAmount,
        uint oldLevel,
        uint newLevel
    ) external virtual override {}

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
        returns (address[] memory rewardTokens, uint[] memory rewardAmounts)
    {
        rewardTokens = new address[](1);
        rewardTokens[0] = rewardToken;

        rewardAmounts = new uint[](1);
        rewardAmounts[0] = pendingToken(relicId, rewardAmount);
    }

    /// @notice Returns the amount of pending rewardToken for a position from this rewarder.
    /// @param rewardAmount Amount of reward token owed for this position from the Reliquary.
    function pendingToken(uint relicId, uint rewardAmount) public view virtual returns (uint pending) {}
}
