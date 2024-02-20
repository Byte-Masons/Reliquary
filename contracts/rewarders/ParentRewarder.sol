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

    event LogRewardMultiplier(uint256 rewardMultiplier);
    event ChildCreated(address indexed child, address indexed token);
    event ChildRemoved(address indexed child);

    /**
     * @dev Contructor called on deployment of this contract.
     * @param _rewardMultiplier Amount to multiply reward by, relative to BASIS_POINTS.
     * @param _rewardToken Address of token rewards are distributed in.
     * @param _reliquary Address of Reliquary this rewarder will read state from.
     */
    constructor(
        uint256 _rewardMultiplier,
        address _rewardToken,
        address _reliquary
    ) MultiplierRewarder(_rewardMultiplier, _rewardToken, _reliquary) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Set the rewardMultiplier to a new value and emit a logging event.
     * Separate role from who can add/remove children.
     * @param _rewardMultiplier Amount to multiply reward by, relative to BASIS_POINTS.
     */
    function setRewardMultiplier(uint256 _rewardMultiplier) external onlyRole(REWARD_SETTER) {
        rewardMultiplier = _rewardMultiplier;
        emit LogRewardMultiplier(_rewardMultiplier);
    }

    /**
     * @notice Deploys a ChildRewarder contract and adds it to the childrenRewarders set.
     * @param _rewardToken Address of token rewards are distributed in.
     * @param _rewardMultiplier Amount to multiply reward by, relative to BASIS_POINTS.
     * @param _owner Address to transfer ownership of the ChildRewarder contract to.
     * @return child_ Address of the new ChildRewarder.
     */
    function createChild(
        address _rewardToken,
        uint256 _rewardMultiplier,
        address _owner
    ) external onlyRole(CHILD_SETTER) returns (address child_) {
        child_ = address(new ChildRewarder(_rewardMultiplier, _rewardToken, reliquary));
        Ownable(child_).transferOwnership(_owner);
        childrenRewarders.add(child_);
        emit ChildCreated(child_, address(_rewardToken));
    }

    /// @notice Removes a ChildRewarder from the childrenRewarders set.
    /// @param _childRewarder Address of the ChildRewarder contract to remove.
    function removeChild(address _childRewarder) external onlyRole(CHILD_SETTER) {
        require(childrenRewarders.remove(_childRewarder), "That is not my child rewarder!");
        emit ChildRemoved(_childRewarder);
    }

    /// Call onReward function of each child.
    /// @inheritdoc SingleAssetRewarder
    function onReward(
        uint256 _relicId,
        uint256 _rewardAmount,
        address _to
    ) external override onlyReliquary {
        super._onReward(_relicId, _rewardAmount, _to);

        for (uint256 i_; i_ < childrenRewarders.length(); ) {
            IRewarder(childrenRewarders.at(i_)).onReward(_relicId, _rewardAmount, _to);
            unchecked {
                ++i_;
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
    function pendingTokens(
        uint256 _relicId,
        uint256 _rewardAmount
    )
        external
        view
        override
        returns (address[] memory rewardTokens_, uint256[] memory rewardAmounts_)
    {
        uint256 length_ = childrenRewarders.length() + 1;
        rewardTokens_ = new address[](length_);
        rewardTokens_[0] = rewardToken;

        rewardAmounts_ = new uint256[](length_);
        rewardAmounts_[0] = pendingToken(_relicId, _rewardAmount);

        for (uint256 i_ = 1; i_ < length_; ) {
            ChildRewarder rewarder_ = ChildRewarder(childrenRewarders.at(i_ - 1));
            rewardTokens_[i_] = rewarder_.rewardToken();
            rewardAmounts_[i_] = rewarder_.pendingToken(_relicId, _rewardAmount);
            unchecked {
                ++i_;
            }
        }
    }
}
