// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

/**
 * @dev The defined function must comply with a few rules:
 *      - it must be strictly increasing
 *      - fnc(0) > 0
 */
interface IFunction {
    function getFunction(uint256 _maturity) external view returns (uint256);
}