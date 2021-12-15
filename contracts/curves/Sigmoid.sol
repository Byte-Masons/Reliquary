pragma solidity ^0.8.0;

contract Sigmoid {

    function curve(uint maturity) external pure returns (uint) {
        int denom = sqrt((int(maturity) - 2e7) ** 2 + 1e14);
        return uint(
            50 * (int(maturity) - 2e7 + denom)
            / denom
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
