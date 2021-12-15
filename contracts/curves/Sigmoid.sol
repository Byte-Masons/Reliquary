pragma solidity ^0.8.0;

contract Sigmoid {

    function curve(uint maturity) external pure returns (uint) {
        uint denom = sqrt(uint((int(maturity) - 2e7) ** 2) + 1e14);
        return uint(
            50 * (int(maturity) - 2e7 + int(denom))
            / int(denom)
        );
    }

    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

}
