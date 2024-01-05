pragma solidity ^0.8.15;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IRollingRewarder.sol";


contract RewardsPool {
    address public immutable RewardToken;
    address public Rewarder;
    uint256 public lastRetrievedTime;
    uint256 public totalRewards;

    constructor(address _rewardToken, address rewarder) {
        RewardToken = _rewardToken;
        Rewarder = rewarder;
        IERC20(RewardToken).approve(Rewarder, type(uint256).max);
    }

    function fundRewarder() external {
        uint256 balance = IERC20(RewardToken).balanceOf(address(this));
        totalRewards += balance;
        IRollingRewarder(Rewarder).fund();
    }
    
}