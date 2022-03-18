// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

contract Sigmoid {
    int256 constant HORIZONTAL_STRETCH = 192307; // TODO: mainnet 1e7
    int256 constant HORIZONTAL_SHIFT = 480769; // TODO: mainnet 25e6
    int256 constant VERTICAL_STRETCH = 50;
    int256 constant VERTICAL_SHIFT = 0; // care must be taken not to allow negative y-values

    function curve(uint256 maturity) external pure returns (uint256) {
        int256 denom = sqrt((int256(maturity) - HORIZONTAL_SHIFT)**2 + HORIZONTAL_STRETCH**2);

        return
            uint256(
                (VERTICAL_STRETCH * ((int256(maturity) - HORIZONTAL_SHIFT) + denom)) / // denom is added to place lower bound at 0
                    denom +
                    VERTICAL_SHIFT
            );
    }

    function sqrt(int256 y) internal pure returns (int256 z) {
        if (y > 3) {
            z = y;
            int256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
