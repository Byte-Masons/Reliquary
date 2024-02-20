// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "contracts/interfaces/IFunction.sol";
import "contracts/interfaces/ICurves.sol";

contract Curves is ICurves {
    IFunction public fnc;

    uint256 private constant ACC_REWARD_PRECISION = 1e45; // Must be the same value as Reliquary.
    uint256 private constant SHIBA_SUPPLY = 589280962856592 ether;

    error Curves__MULTIPLIER_AT_MATURITY_ZERO_SHOULD_BE_GT_ZERO();
    error Curves__REWARD_PRECISION_ISSUE();
    error Curves__UNSORTED_MATURITY_LEVELS();

    constructor(IFunction _fnc) {
        if (_fnc.getFunction(0) == 0)
            revert Curves__MULTIPLIER_AT_MATURITY_ZERO_SHOULD_BE_GT_ZERO();

        // All SHIBA supply in 10 years should not round down at 0 in case of division
        if (ACC_REWARD_PRECISION < SHIBA_SUPPLY * _fnc.getFunction(365 days * 10))
            revert Curves__REWARD_PRECISION_ISSUE();

        fnc = _fnc;
    }

    /**
     * @notice Get the multiplier from a level.
     * @param _level The level.
     * @return Sampled multiplier.
     */
    function getMultiplerFromLevel(
        uint256 _level
    ) external view returns (uint256) {
        return fnc.getFunction(_level);
    }
}
