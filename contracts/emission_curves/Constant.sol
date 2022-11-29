// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "../interfaces/IEmissionCurve.sol";

contract Constant is IEmissionCurve {
    function getRate(uint) external pure override returns (uint rate) {
        rate = 1e17;
    }
}
