// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract DichotomousSearch is Test {
    TestDichotomousSearch public testDichotomousSearch;

    function setUp() public {
        testDichotomousSearch = new TestDichotomousSearch();
    }

    /// levelOnUpdateDichotomous and levelOnUpdateNormal must always return the same result.
    function testDichotomousVsNormal(uint32 entry, uint32 timestamp) public {
        vm.assume(entry <= timestamp);
        vm.assume(timestamp - entry <= 356);


        assertEq(
            testDichotomousSearch.levelOnUpdateDichotomous(entry, timestamp),
            testDichotomousSearch.levelOnUpdateNormal(entry, timestamp)
        );
    }
}

contract TestDichotomousSearch {
    uint256 numLevels = 200; // < to config
    uint256[] requiredMaturity = new uint256[](numLevels);
    //uint[] public requiredMaturity = [0, 1 days, 7 days, 14 days, 30 days, 90 days, 180 days, 365 days];

    constructor() {
        uint256 minRequiredMaturity = 0;
        uint256 maxRequiredMaturity = 356;

        uint256 maturityStep = (maxRequiredMaturity - minRequiredMaturity) /
            (numLevels - 1);

        for (uint256 i = 0; i < numLevels; i++) {
            requiredMaturity[i] = minRequiredMaturity + i * maturityStep;
        }
    }

    function levelOnUpdateNormal(
        uint entry,
        uint timestamp
    ) public view returns (uint level) {
        uint length = requiredMaturity.length;
        if (length == 1) {
            return 0;
        }

        uint maturity = timestamp - entry;
        for (level = length - 1; true; ) {
            if (maturity >= requiredMaturity[level]) {
                break;
            }
            unchecked {
                --level;
            }
        }
    }

    function levelOnUpdateDichotomous(
        uint entry,
        uint timestamp
    ) public view returns (uint level) {
        uint length = requiredMaturity.length;
        if (length == 1) {
            return 0;
        }

        uint maturity = timestamp - entry;
        uint low = 0;
        uint high = length - 1;
        while (low < high) {
            uint mid = (low + high + 1) / 2;
            if (maturity >= requiredMaturity[mid]) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }
        return low;
    }
}
