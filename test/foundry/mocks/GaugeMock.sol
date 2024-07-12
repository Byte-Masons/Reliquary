// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GaugeMock {
    address public token;

    constructor(address _token) {
        token = _token;
    }

    mapping (address => uint256) public balanceOf;
    mapping (address => uint256) public rewardOf;
    
    function deposit(uint256 amount, uint256) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        balanceOf[msg.sender] += amount;
    }
    
    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "GaugeMock: insufficient balance");
        IERC20(token).transfer(msg.sender, amount);
        balanceOf[msg.sender] -= amount;
    }
    
    function getReward(address account, address[] memory tokens) external {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).transfer(account, rewardOf[account]);
        }
        rewardOf[account] = 0;
    }
    
    function setReward(address account, uint256 amount) external {
        rewardOf[account] = amount;
    }
}