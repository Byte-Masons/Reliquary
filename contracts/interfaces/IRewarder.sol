// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IRewarder {
    function onOathReward(
        uint relicId,
        address to,
        uint256 oathAmount
    ) external;

    function onOathDeposit(
        uint relicId,
        address to,
        uint256 depositAmount
    ) external;

    function onOathWithdraw(
        uint relicId,
        address to,
        uint256 withdrawalAmount
    ) external;

    function pendingTokens(
        uint256 pid,
        address user,
        uint256 oathAmount
    ) external view returns (IERC20[] memory, uint256[] memory);
}
