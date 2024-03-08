// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IRewarder.sol";

interface IRollingRewarder is IRewarder {
    function fund(uint256 _amount) external;
}
