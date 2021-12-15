pragma solidity ^0.8.0;

contract Sigmoid {

    int constant HORIZONTAL_STRETCH = 1e7;
    int constant HORIZONTAL_SHIFT = 2e7;
    int constant VERTICAL_STRETCH = 50;
    int constant VERTICAL_SHIFT = 0;

    function curve(uint maturity) external pure returns (uint) {
        int denom = sqrt((int(maturity) - HORIZONTAL_SHIFT) ** 2 + HORIZONTAL_STRETCH ** 2);

        return uint(
            VERTICAL_STRETCH * ((int(maturity) - HORIZONTAL_SHIFT) + denom)
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
