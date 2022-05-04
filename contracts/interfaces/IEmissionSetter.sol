// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IEmissionSetter {
    function getRate() external view returns (uint rate);
}
