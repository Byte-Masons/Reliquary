// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

contract Constant {
    function getRate() external pure returns (uint256 rate) {
        rate = 1e14;
    }
}
