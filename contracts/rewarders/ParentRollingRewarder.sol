// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./RollingRewarder.sol";
import "../interfaces/IParentRollingRewarder.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

/// @title Extension to the SingleAssetRewarder contract that allows managing multiple reward tokens via access control
/// and enumerable children contracts.
contract ParentRollingRewarder is IParentRollingRewarder, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private childrenRewarders;

    uint256 public poolId = type(uint256).max;
    address public reliquary;

    // Errors
    error ParentRollingRewarder__ONLY_RELIQUARY_ACCESS();
    error ParentRollingRewarder__ONLY_CHILD_CAN_BE_REMOVED();
    error ParentRollingRewarder__ALREADY_INITIALIZED();

    // Events
    event ChildCreated(address indexed _child, address indexed _token);
    event ChildRemoved(address indexed _child);

    modifier onlyReliquary() {
        if (msg.sender != reliquary) revert ParentRollingRewarder__ONLY_RELIQUARY_ACCESS();
        _;
    }

    constructor() {}

    /**
     * @dev initialize called in Reliquary.addPool or Reliquary.modifyPool()
     * @param _poolId ID of the pool this rewarder will read state from.
     */
    function initialize(uint256 _poolId) external {
        if (poolId != type(uint256).max || reliquary != address(0)) {
            revert ParentRollingRewarder__ALREADY_INITIALIZED();
        }
        poolId = _poolId;
        reliquary = msg.sender;
    }

    /**
     * @notice Deploys a ChildRewarder contract and adds it to the childrenRewarders set.
     * @param _rewardToken Address of token rewards are distributed in.
     * @return child_ Address of the new ChildRewarder.
     */
    function createChild(address _rewardToken) external onlyOwner returns (address child_) {
        child_ = address(new RollingRewarder(_rewardToken, reliquary, poolId));
        childrenRewarders.add(child_);
        emit ChildCreated(child_, address(_rewardToken));
    }

    /**
     * @notice Removes a ChildRewarder from the childrenRewarders set.
     * @param _childRewarder Address of the ChildRewarder contract to remove.
     */
    function removeChild(address _childRewarder) external onlyOwner {
        if (!childrenRewarders.remove(_childRewarder)) {
            revert ParentRollingRewarder__ONLY_CHILD_CAN_BE_REMOVED();
        }
        emit ChildRemoved(_childRewarder);
    }

    /// Call onReward function of each child.
    function onReward(
        ICurves _curve,
        uint256 _relicId,
        uint256 _rewardAmount,
        address _to,
        uint256 _oldAmount,
        uint256 _oldLevel,
        uint256 _newLevel
    ) external override onlyReliquary {
        uint256 length_ = childrenRewarders.length();

        for (uint256 i_; i_ < length_;) {
            IRewarder(childrenRewarders.at(i_)).onReward(
                _curve, _relicId, _rewardAmount, _to, _oldAmount, _oldLevel, _newLevel
            );
            unchecked {
                ++i_;
            }
        }
    }

    function onDeposit(
        ICurves _curve,
        uint256 _relicId,
        uint256 _depositAmount,
        uint256 _oldAmount,
        uint256 _oldLevel,
        uint256 _newLevel
    ) external override onlyReliquary {
        uint256 length_ = childrenRewarders.length();

        for (uint256 i_; i_ < length_;) {
            IRewarder(childrenRewarders.at(i_)).onDeposit(
                _curve, _relicId, _depositAmount, _oldAmount, _oldLevel, _newLevel
            );
            unchecked {
                ++i_;
            }
        }
    }

    function onWithdraw(
        ICurves _curve,
        uint256 _relicId,
        uint256 _withdrawAmount,
        uint256 _oldAmount,
        uint256 _oldLevel,
        uint256 _newLevel
    ) external override onlyReliquary {
        uint256 length_ = childrenRewarders.length();

        for (uint256 i_; i_ < length_;) {
            IRewarder(childrenRewarders.at(i_)).onWithdraw(
                _curve, _relicId, _withdrawAmount, _oldAmount, _oldLevel, _newLevel
            );
            unchecked {
                ++i_;
            }
        }
    }

    function onSplit(
        ICurves _curve,
        uint256 _fromId,
        uint256 _newId,
        uint256 _amount,
        uint256 _fromAmount,
        uint256 _level
    ) external override onlyReliquary {
        uint256 length_ = childrenRewarders.length();

        for (uint256 i_; i_ < length_;) {
            IRewarder(childrenRewarders.at(i_)).onSplit(
                _curve, _fromId, _newId, _amount, _fromAmount, _level
            );
            unchecked {
                ++i_;
            }
        }
    }

    function onShift(
        ICurves _curve,
        uint256 _fromId,
        uint256 _toId,
        uint256 _amount,
        uint256 _oldFromAmount,
        uint256 _oldToAmount,
        uint256 _fromLevel,
        uint256 _oldToLevel,
        uint256 _newToLevel
    ) external override onlyReliquary {
        uint256 length_ = childrenRewarders.length();

        for (uint256 i_; i_ < length_;) {
            IRewarder(childrenRewarders.at(i_)).onShift(
                _curve,
                _fromId,
                _toId,
                _amount,
                _oldFromAmount,
                _oldToAmount,
                _fromLevel,
                _oldToLevel,
                _newToLevel
            );
            unchecked {
                ++i_;
            }
        }
    }

    function onMerge(
        ICurves _curve,
        uint256 _fromId,
        uint256 _toId,
        uint256 _fromAmount,
        uint256 _toAmount,
        uint256 _fromLevel,
        uint256 _oldToLevel,
        uint256 _newToLevel
    ) external override onlyReliquary {
        uint256 length_ = childrenRewarders.length();

        for (uint256 i_; i_ < length_;) {
            IRewarder(childrenRewarders.at(i_)).onMerge(
                _curve, _fromId, _toId, _fromAmount, _toAmount, _fromLevel, _oldToLevel, _newToLevel
            );
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

    function pendingTokens(uint256 _relicId)
        external
        view
        override
        returns (address[] memory rewardTokens_, uint256[] memory rewardAmounts_)
    {
        uint256 length_ = childrenRewarders.length();
        rewardTokens_ = new address[](length_);
        rewardAmounts_ = new uint256[](length_);

        for (uint256 i_ = 0; i_ < length_;) {
            RollingRewarder rewarder_ = RollingRewarder(childrenRewarders.at(i_));
            rewardTokens_[i_] = rewarder_.rewardToken();
            rewardAmounts_[i_] = rewarder_.pendingToken(_relicId);
            unchecked {
                ++i_;
            }
        }
    }
}
