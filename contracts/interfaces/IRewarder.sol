// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

interface IRewarder {
    function onReward(uint relicId, uint rewardAmount, address to) external;

    function onDeposit(uint relicId, uint depositAmount) external;

    function onWithdraw(uint relicId, uint withdrawalAmount) external;

    function pendingTokens(uint relicId, uint rewardAmount) external view returns (address[] memory, uint[] memory);
}
