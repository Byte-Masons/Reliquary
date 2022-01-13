// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;
import "../OZ/token/ERC20/utils/SafeERC20.sol";
interface IRewarder {
    function onRelicReward(uint256 pid, address user, address recipient, uint256 sushiAmount, uint256 newLpAmount) external;
    function pendingTokens(uint256 pid, address user, uint256 sushiAmount) external view returns (IERC20[] memory, uint256[] memory);
}
