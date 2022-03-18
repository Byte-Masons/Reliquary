// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

library SignedSafeMath {
    int256 private constant _INT256_MIN = -2**255;

    function toUInt256(int256 a) internal pure returns (uint256) {
        require(a >= 0, "Integer < 0");
        return uint256(a);
    }
}
