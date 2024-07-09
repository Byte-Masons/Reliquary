// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VoterMock {
    mapping(address => address) public gauges;
    mapping(address => mapping(address => uint256)) public pendingRewards;

    constructor() {}

    function setGauge(address poolToken, address gauge) public {
        gauges[poolToken] = gauge;
    }
    
    function isAlive(address) public pure returns (bool) {
        return true;
    }
    
    function claimRewards(
        address[] memory _gauges,
        address[][] memory _tokens
    ) external {
        for (uint256 i = 0; i < _gauges.length; i++) {
            for (uint256 j = 0; j < _tokens[i].length; j++) {
                IERC20(_tokens[i][j]).transfer(msg.sender, pendingRewards[_gauges[i]][_tokens[i][j]]);
                pendingRewards[_gauges[i]][_tokens[i][j]] = 0;
            }
        }
    }
    
    function setPendingRewards(
        address gauge,
        address[] memory tokens,
        uint256[] memory amounts
    ) external {
        for (uint256 i = 0; i < tokens.length; i++) {
            pendingRewards[gauge][tokens[i]] = amounts[i];
        }
    }
}