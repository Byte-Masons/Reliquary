// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface ICurves {
    function getLevelFromMaturity(uint256 _maturity) external view returns (uint256);

    function getMultiplerFromLevel(uint256 _level) external view returns (uint256);

    function getSamplingPeriod() external view returns (uint256);

    function getNbLevel() external view returns (uint256);
}
