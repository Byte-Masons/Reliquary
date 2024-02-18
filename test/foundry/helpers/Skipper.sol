// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

contract Skipper is Test {
    function doSkip(uint time) external {
        time = bound(time, 1, 3650 days);
        skip(time);
    }
}
