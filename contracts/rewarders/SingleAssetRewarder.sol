// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "../interfaces/IRewarder.sol";

abstract contract SingleAssetRewarder is IRewarder {
    address public immutable rewardToken;
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
     * @param _rewardAmount Amount of reward token owed for this position from the Reliquary.
     * @param _to Address to send rewards to.
     */
    function onReward(uint256 _relicId, uint256 _rewardAmount, address _to) external virtual override {}

    /// @notice Called by Reliquary _deposit function.
    function onDeposit(uint256 _relicId, uint256 _depositAmount) external virtual override {}

    /// @notice Called by Reliquary withdraw or withdrawAndHarvest function.
    function onWithdraw(uint256 _relicId, uint256 _withdrawalAmount) external virtual override {}

    /**
     * @notice Returns the amount of pending tokens for a position from this rewarder.
     * Interface supports multiple tokens.
     * @param _relicId The NFT ID of the position.
     * @param _rewardAmount Amount of reward token owed for this position from the Reliquary.
     */
    function pendingTokens(uint256 _relicId, uint256 _rewardAmount)
        external
        view
        virtual
        override
        returns (address[] memory rewardTokens_, uint256[] memory rewardAmounts_)
    {
        rewardTokens_ = new address[](1);
        rewardTokens_[0] = rewardToken;

        rewardAmounts_ = new uint256[](1);
        rewardAmounts_[0] = pendingToken(_relicId, _rewardAmount);
    }
    /**
     * @notice Returns the amount of pending rewardToken for a position from this rewarder.
     * @param _relicId The NFT ID of the position.
     * @param _rewardAmount Amount of reward token owed for this position from the Reliquary.
     */
    function pendingToken(uint256 _relicId, uint256 _rewardAmount) public view virtual returns (uint256 pending_) {}
}
