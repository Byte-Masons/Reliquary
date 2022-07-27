// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

contract Constant {
    function getRate() external pure returns (uint rate) {
        rate = 1e17;
    }
}
