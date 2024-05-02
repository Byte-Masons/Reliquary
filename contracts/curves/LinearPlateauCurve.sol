// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "contracts/interfaces/ICurves.sol";

contract LinearPlateauCurve is ICurves {
    uint256 public immutable slope;
    uint256 public immutable minMultiplier; // getFunction(0) = minMultiplier
    uint256 public immutable plateauLevel; // getFunction(0) = minMultiplier

    error LinearFunction__MIN_MULTIPLIER_MUST_GREATER_THAN_ZERO();

    constructor(uint256 _slope, uint256 _minMultiplier, uint256 _plateauLevel) {
        if (_minMultiplier == 0) revert LinearFunction__MIN_MULTIPLIER_MUST_GREATER_THAN_ZERO();
        slope = _slope; // uint256 force the "strictly increasing" rule
        minMultiplier = _minMultiplier;
        plateauLevel = _plateauLevel;
    }

    function getFunction(uint256 _level) external view returns (uint256) {
        if (_level >= plateauLevel) return plateauLevel * slope + minMultiplier;
        return _level * slope + minMultiplier;
    }
}
