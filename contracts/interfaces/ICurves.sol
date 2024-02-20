// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface ICurves {
    function getMultiplerFromLevel(uint256 _level) external view returns (uint256);
}
