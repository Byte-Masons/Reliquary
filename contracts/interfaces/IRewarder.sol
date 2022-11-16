// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IRewarder {
    function onReward(
        uint relicId,
        uint rewardAmount,
        address to
    ) external;

    function onDeposit(
        uint relicId,
        uint depositAmount
    ) external;

    function onWithdraw(
        uint relicId,
        uint withdrawalAmount
    ) external;

    function pendingTokens(
        uint relicId,
        uint rewardAmount
    ) external view returns (IERC20[] memory, uint[] memory);
}
