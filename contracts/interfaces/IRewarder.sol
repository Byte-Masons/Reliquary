// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IRewarder {
    function onOathReward(
        uint relicId,
        uint oathAmount
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
        uint oathAmount
    ) external view returns (IERC20[] memory, uint[] memory);
}
