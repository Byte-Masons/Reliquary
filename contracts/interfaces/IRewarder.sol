// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IRewarder {
    function onOathReward(
        uint relicId,
        address to,
        uint oathAmount
    ) external;

    function onOathDeposit(
        uint relicId,
        address to,
        uint depositAmount
    ) external;

    function onOathWithdraw(
        uint relicId,
        address to,
        uint withdrawalAmount
    ) external;

    function pendingTokens(
        uint pid,
        address user,
        uint oathAmount
    ) external view returns (IERC20[] memory, uint[] memory);
}
