// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "../interfaces/IRollingRewarder.sol";


contract RewardsPool is Ownable {
    address public immutable rewardToken;
    address public immutable rewarder;
    uint256 public totalRewards;

    constructor(address _rewardToken, address _rewarder) {
        rewardToken = _rewardToken;
        rewarder = _rewarder;
        IERC20(_rewardToken).approve(_rewarder, type(uint256).max);
    }

    function fundRewarder() external onlyOwner {
        uint256 balance = IERC20(rewardToken).balanceOf(address(this));
        totalRewards += balance;
        IRollingRewarder(rewarder).fund();
    }
    
}
