// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface ICurves {
    function getFunction(uint256 _maturity) external view returns (uint256);
}
