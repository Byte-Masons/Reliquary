// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

interface IRewarder {
    function onReward(
        uint relicId,
        uint rewardAmount,
        address to,
        uint amount,
        uint oldLevel,
        uint newLevel
    ) external;

    function onDeposit(
        uint relicId,
        uint depositAmount,
        uint oldAmount,
        uint oldLevel,
        uint newLevel
    ) external;

    function onWithdraw(
        uint relicId,
        uint withdrawalAmount,
        uint oldAmount,
        uint oldLevel,
        uint newLevel
    ) external;

    function onSplit(
        uint fromId,
        uint newId,
        uint amount,
        uint fromAmount,
        uint level
    ) external;

    function onShift(
        uint fromId,
        uint toId,
        uint amount,
        uint oldFromAmount,
        uint oldToAmount,
        uint fromLevel,
        uint oldToLevel,
        uint newToLevel
    ) external;

    function onMerge(
        uint fromId,
        uint toId,
        uint fromAmount,
        uint toAmount,
        uint fromLevel,
        uint oldToLevel,
        uint newToLevel
    ) external;

    function pendingTokens(
        uint relicId,
        uint rewardAmount
    ) external view returns (address[] memory, uint[] memory);
}
