// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IMockVoter {
    function gauges(address _pair) external view returns (address);
    function setGauge(address poolToken, address gauge) external;   
}
