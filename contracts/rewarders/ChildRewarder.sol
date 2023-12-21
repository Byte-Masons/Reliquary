// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "../interfaces/IRewarder.sol";

/// @title Child rewarder contract to be deployed and called by a ParentRewarder, rather than directly by the Reliquary.
abstract contract ChildRewarder is IRewarder {
    /// @notice Address of ParentRewarder which deployed this contract
    address public immutable parent;

    modifier onlyParent() {
        require(
            msg.sender == address(parent),
            "Only parent can call this function."
        );
        _;
    }

    /**
     * @dev Contructor called on deployment of this contract.
     */
    constructor() {
        parent = msg.sender;
    }
}
