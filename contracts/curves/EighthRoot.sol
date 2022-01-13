// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library EighthRoot {
    function curve(uint256 maturity) external pure returns (uint256) {
        uint256 juniorCurve = sqrt(maturity / 4) / 5;
        uint256 seniorCurve = sqrt(sqrt(maturity)) / 2;

        return min(juniorCurve, seniorCurve);
    }

    // just use solidity Math library that already has min function?
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
