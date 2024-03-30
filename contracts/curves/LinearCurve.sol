// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "contracts/interfaces/ICurves.sol";

contract LinearCurve is ICurves {
    uint256 public immutable slope;
    uint256 public immutable minMultiplier; // getFunction(0) = minMultiplier

    error LinearFunction__MIN_MULTIPLIER_MUST_GREATER_THAN_ZERO();

    constructor(uint256 _slope, uint256 _minMultiplier) {
        if (_minMultiplier == 0) revert LinearFunction__MIN_MULTIPLIER_MUST_GREATER_THAN_ZERO();
        slope = _slope; // uint256 force the "strictly increasing" rule
        minMultiplier = _minMultiplier;
    }

    function getFunction(uint256 _maturity) external view returns (uint256) {
        return _maturity * slope + minMultiplier;
    }
}
