// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "contracts/interfaces/IFunction.sol";

contract LinearPlateauFunction is IFunction {
    uint256 public slope;
    uint256 public minMultiplier; // getFunction(0) = minMultiplier
    uint256 public plateauLevel; // getFunction(0) = minMultiplier

    error LinearFunction__MIN_MULTIPLIER_MUST_GREATER_THAN_ZERO();

    constructor(uint256 _slope, uint256 _minMultiplier, uint256 _plateauLevel) {
        if (_minMultiplier == 0)
            revert LinearFunction__MIN_MULTIPLIER_MUST_GREATER_THAN_ZERO();
        slope = _slope; // uint256 force the "strictly increasing" rule
        minMultiplier = _minMultiplier;
        plateauLevel = _plateauLevel;
    }

    function getFunction(uint256 _maturity) external view returns (uint256) {
        if (_maturity >= plateauLevel) return plateauLevel * slope + minMultiplier;
        return _maturity * slope + minMultiplier;
    }
}
