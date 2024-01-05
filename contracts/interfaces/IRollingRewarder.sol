// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "./IRewarder.sol";

interface IRollingRewarder is IRewarder {

    function fund() external;

    function setRewardsPool(address _rewardsPool) external;
}
