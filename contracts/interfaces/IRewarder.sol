// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IRewarder {
    function onOathReward(
        uint256 pid,
        address user,
        address recipient,
        uint256 oathAmount,
        uint256 newLpAmount
    ) external;

    function pendingTokens(
        uint256 pid,
        address user,
        uint256 oathAmount
    ) external view returns (IERC20[] memory, uint256[] memory);
}
