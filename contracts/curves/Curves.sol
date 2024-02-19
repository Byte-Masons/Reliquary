// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "contracts/interfaces/IFunction.sol";
import "contracts/interfaces/ICurves.sol";

contract Curves is ICurves {
    IFunction public fnc;
    uint256 internal samplingPeriod;
    uint256 internal nbLevel;

    uint256 private constant ACC_REWARD_PRECISION = 1e45; // Must be the same value as Reliquary.
    uint256 private constant SHIBA_SUPPLY = 589280962856592 ether;

    error Curves__SAMPLING_PERIOD_SHOULD_BE_GT_ZERO();
    error Curves__NB_LEVEL_SHOULD_BE_GT_ZERO();
    error Curves__MULTIPLIER_AT_MATURITY_ZERO_SHOULD_BE_GT_ZERO();
    error Curves__REWARD_PRECISION_ISSUE();
    error Curves__UNSORTED_MATURITY_LEVELS();

    constructor(IFunction _fnc, uint256 _samplingPeriod, uint256 _nbLevel) {
        if (_samplingPeriod == 0)
            revert Curves__SAMPLING_PERIOD_SHOULD_BE_GT_ZERO();

        if (_nbLevel == 0) 
            revert Curves__NB_LEVEL_SHOULD_BE_GT_ZERO();

        if (_fnc.getFunction(0) == 0)
            revert Curves__MULTIPLIER_AT_MATURITY_ZERO_SHOULD_BE_GT_ZERO();

        // All SHIBA supply on last level should not round down at 0 in case of division
        if (ACC_REWARD_PRECISION < SHIBA_SUPPLY * _fnc.getFunction(_samplingPeriod * (_nbLevel - 1)))
            revert Curves__REWARD_PRECISION_ISSUE();


        fnc = _fnc;
        samplingPeriod = _samplingPeriod;
        nbLevel = _nbLevel;

        //! This check is nice to have but can limit the number of level accepted because of gas
        // if (_nbLevel > 1) {
        //     uint highestMaturity;
        //     for (uint i = 0; i < _nbLevel;) {
        //         uint256 mat = _fnc.getFunction(i);
        //         if (mat <= highestMaturity) revert Curves__UNSORTED_MATURITY_LEVELS();
        //         highestMaturity = mat;
        //         unchecked {
        //             ++i;
        //         }
        //     }
        // }
    }

    /**
     * @notice Get the sampled level from a maturity.
     * @dev Once max level reached this function return nbLevel.
     * @param _maturity Position maturity.
     * @return Sampled level.
     */
    function getLevelFromMaturity(
        uint256 _maturity
    ) external view returns (uint256) {
        uint256 level_ = _maturity / samplingPeriod;

        if (level_ < nbLevel - 1) {
            return level_;
        } else {
            return nbLevel - 1;
        }
    }

    /**
     * @notice Get the multiplier from a level.
     * @param _level The level.
     * @return Sampled multiplier.
     */
    function getMultiplerFromLevel(
        uint256 _level
    ) external view returns (uint256) {
        return fnc.getFunction(samplingPeriod * _level);
    }

    // ---- getter ----

    function getSamplingPeriod() external view returns (uint256) {
        return samplingPeriod;
    }

    function getNbLevel() external view returns (uint256) {
        return nbLevel;
    }
}
