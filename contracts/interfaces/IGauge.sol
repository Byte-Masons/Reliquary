// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IGauge {
    function notifyRewardAmount(address token, uint amount) external;
    function getReward(address account, address[] memory tokens) external;
    function claimFees() external returns (uint claimed0, uint claimed1);
    function left(address token) external view returns (uint);
    function rewardRate(address _pair) external view returns (uint);
    function balanceOf(address _account) external view returns (uint);
    function isForPair() external view returns (bool);
    function totalSupply() external view returns (uint);
    function earned(address token, address account) external view returns (uint);
    function deposit(uint256 amount, uint256 tokenId) external;
    function withdraw(uint256 amount) external;
}
