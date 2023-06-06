// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ChildRewarder.sol";
import "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";

/// @title Extension to the SingleAssetRewarder contract that allows managing multiple reward tokens via access control
/// and enumerable children contracts.
contract ParentRewarder is MultiplierRewarder, AccessControlEnumerable {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private childrenRewarders;

    /// @dev Access control roles.
    bytes32 public constant REWARD_SETTER = keccak256("REWARD_SETTER");
    bytes32 public constant CHILD_SETTER = keccak256("CHILD_SETTER");

    event LogRewardMultiplier(uint rewardMultiplier);
    event ChildCreated(address indexed child, address indexed token);
    event ChildRemoved(address indexed child);

    /**
     * @dev Contructor called on deployment of this contract.
     * @param _rewardMultiplier Amount to multiply reward by, relative to BASIS_POINTS.
     * @param _rewardToken Address of token rewards are distributed in.
     * @param _reliquary Address of Reliquary this rewarder will read state from.
     */
    constructor(uint _rewardMultiplier, address _rewardToken, address _reliquary)
        MultiplierRewarder(_rewardMultiplier, _rewardToken, _reliquary)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Set the rewardMultiplier to a new value and emit a logging event.
     * Separate role from who can add/remove children.
     * @param _rewardMultiplier Amount to multiply reward by, relative to BASIS_POINTS.
     */
    function setRewardMultiplier(uint _rewardMultiplier) external onlyRole(REWARD_SETTER) {
        rewardMultiplier = _rewardMultiplier;
        emit LogRewardMultiplier(_rewardMultiplier);
    }

    /**
     * @notice Deploys a ChildRewarder contract and adds it to the childrenRewarders set.
     * @param _rewardToken Address of token rewards are distributed in.
     * @param _rewardMultiplier Amount to multiply reward by, relative to BASIS_POINTS.
     * @param owner Address to transfer ownership of the ChildRewarder contract to.
     * @return child Address of the new ChildRewarder.
     */
    function createChild(address _rewardToken, uint _rewardMultiplier, address owner)
        external
        onlyRole(CHILD_SETTER)
        returns (address child)
    {
        child = address(new ChildRewarder(_rewardMultiplier, _rewardToken, reliquary));
        Ownable(child).transferOwnership(owner);
        childrenRewarders.add(child);
        emit ChildCreated(child, address(_rewardToken));
    }

    /// @notice Removes a ChildRewarder from the childrenRewarders set.
    /// @param childRewarder Address of the ChildRewarder contract to remove.
    function removeChild(address childRewarder) external onlyRole(CHILD_SETTER) {
        require(childrenRewarders.remove(childRewarder), "That is not my child rewarder!");
        emit ChildRemoved(childRewarder);
    }

    /// Call onReward function of each child.
    /// @inheritdoc SingleAssetRewarder
    function onReward(uint relicId, uint rewardAmount, address to) external override onlyReliquary {
        super._onReward(relicId, rewardAmount, to);

        uint length = childrenRewarders.length();
        for (uint i; i < length;) {
            IRewarder(childrenRewarders.at(i)).onReward(relicId, rewardAmount, to);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev WARNING: This operation will copy the entire childrenRewarders storage to memory, which can be quite
     * expensive. This is designed to mostly be used by view accessors that are queried without any gas fees.
     * Developers should keep in mind that this function has an unbounded cost, and using it as part of a state-
     * changing function may render the function uncallable if the set grows to a point where copying to memory
     * consumes too much gas to fit in a block.
     */
    function getChildrenRewarders() external view returns (address[] memory) {
        return childrenRewarders.values();
    }

    /// @inheritdoc SingleAssetRewarder
    function pendingTokens(uint relicId, uint rewardAmount)
        external
        view
        override
        returns (address[] memory rewardTokens, uint[] memory rewardAmounts)
    {
        uint length = childrenRewarders.length() + 1;
        rewardTokens = new address[](length);
        rewardTokens[0] = rewardToken;

        rewardAmounts = new uint[](length);
        rewardAmounts[0] = pendingToken(relicId, rewardAmount);

        for (uint i = 1; i < length;) {
            ChildRewarder rewarder = ChildRewarder(childrenRewarders.at(i - 1));
            rewardTokens[i] = rewarder.rewardToken();
            rewardAmounts[i] = rewarder.pendingToken(relicId, rewardAmount);
            unchecked {
                ++i;
            }
        }
    }
}
