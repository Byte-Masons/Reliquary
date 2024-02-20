// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

interface IRewarder {
    function onReward(uint256 _relicId, uint256 _rewardAmount, address _to) external;

    function onDeposit(uint256 _relicId, uint256 _depositAmount) external;

    function onWithdraw(uint256 _relicId, uint256 _withdrawalAmount) external;

    function pendingTokens(
        uint256 _relicId,
        uint256 _rewardAmount
    ) external view returns (address[] memory, uint256[] memory);
}
