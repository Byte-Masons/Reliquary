// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface IEmissionSetter {
    function getRate() external view returns (uint256 rate);
}
