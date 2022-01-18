// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface ICurve {
    function curve(uint256 maturity) external pure returns (uint256);
}
