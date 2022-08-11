// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

contract Skipper is Test {
    function doSkip(uint40 time) external {
        skip(time);
    }
}
