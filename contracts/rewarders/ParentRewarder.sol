// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./SingleAssetRewarderOwnable.sol";
import "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";

contract ParentRewarder is SingleAssetRewarder, AccessControlEnumerable {

    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private childrenRewarders;

    bytes32 private constant REWARD_SETTER = keccak256("REWARD_SETTER");
    bytes32 private constant CHILD_SETTER = keccak256("CHILD_SETTER");

    event LogRewardMultiplier(uint rewardMultiplier);
    event ChildCreated(address indexed child, address indexed token);
    event ChildRemoved(address indexed child);

    /// @notice Contructor called on deployment of this contract
    /// @param _rewardMultiplier Amount to multiply reward by, relative to BASIS_POINTS
    /// @param _rewardToken Address of token rewards are distributed in
    /// @param _reliquary Address of Reliquary this rewarder will read state from
    constructor(
        uint _rewardMultiplier,
        IERC20 _rewardToken,
        IReliquary _reliquary
    ) SingleAssetRewarder(_rewardMultiplier, _rewardToken, _reliquary) {}

    function setRewardMultiplier(uint _rewardMultiplier) external onlyRole(REWARD_SETTER) {
        rewardMultiplier = _rewardMultiplier;
        emit LogRewardMultiplier(_rewardMultiplier);
    }

    function createChild(IERC20 _rewardToken, uint _rewardMultiplier) external onlyRole(CHILD_SETTER) {
        SingleAssetRewarderOwnable child = new SingleAssetRewarderOwnable(_rewardMultiplier, _rewardToken, reliquary);
        Ownable(address(child)).transferOwnership(msg.sender);
        childrenRewarders.add(address(child));
        emit ChildCreated(address(child), address(_rewardToken));
    }

    function removeChild(address childRewarder) external onlyRole(CHILD_SETTER) {
        if(!childrenRewarders.remove(childRewarder))
            revert("That is not my child rewarder!");
        emit ChildRemoved(childRewarder);
    }

    //* WARNING: This operation will copy the entire childrenRewarders storage to memory, which can be quite expensive. This is designed
    //* to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
    //* this function has an unbounded cost, and using it as part of a state-changing function may render the function
    //* uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
    function getChildrenRewarders() external view returns (address[] memory) {
        return childrenRewarders.values();
    }

    /// @notice Called by Reliquary harvest or withdrawAndHarvest function
    /// @param rewardAmount Amount of reward token owed for this position from the Reliquary
    /// @param to Address to send rewards to
    function onReward(
        uint, //relicId
        uint rewardAmount,
        address to
    ) external override onlyReliquary {
        if (rewardMultiplier != 0) {
            rewardToken.safeTransfer(to, pendingToken(rewardAmount));
        }
        emit LogOnReward(rewardAmount, to);

        uint len = childrenRewarders.length();
        for(uint i; i < len;) {
            IRewarder(childrenRewarders.at(i)).onReward(0, rewardAmount, to);
            unchecked {++i;}
        }
    }
}
