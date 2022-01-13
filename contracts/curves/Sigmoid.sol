// SPDX-License-Identifier: MIT
// EXPERIMENTAL - NO NEED TO AUDIT THIS FILE

pragma solidity ^0.8.0;

contract Sigmoid {

    int constant HORIZONTAL_STRETCH = 1e7;
    int constant HORIZONTAL_SHIFT = 25e6;
    int constant VERTICAL_STRETCH = 50;
    int constant VERTICAL_SHIFT = 0; // care must be taken not to allow negative y-values

    function curve(uint maturity) external pure returns (uint) {
        int denom = sqrt((int(maturity) - HORIZONTAL_SHIFT) ** 2 + HORIZONTAL_STRETCH ** 2);

        return uint(
            VERTICAL_STRETCH * ((int(maturity) - HORIZONTAL_SHIFT) + denom) // denom is added to place lower bound at 0
            / denom + VERTICAL_SHIFT
        );
    }

    function sqrt(int y) internal pure returns (int z) {
        if (y > 3) {
            z = y;
            int x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

}
