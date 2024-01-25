// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./RollingRewarder.sol";
import "../interfaces/IRewarder.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";

/// @title Extension to the SingleAssetRewarder contract that allows managing multiple reward tokens via access control
/// and enumerable children contracts.
contract ParentRewarderRolling is IRewarder, AccessControlEnumerable {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private childrenRewarders;

    uint public immutable poolId;
    address public immutable reliquary;

    /// @dev Access control roles.
    bytes32 public constant REWARD_SETTER = keccak256("REWARD_SETTER");
    bytes32 public constant CHILD_SETTER = keccak256("CHILD_SETTER");

    event ChildCreated(address indexed child, address indexed token);
    event ChildRemoved(address indexed child);

    /// @dev Limits function calls to address of Reliquary contract `reliquary`
    modifier onlyReliquary() {
        require(msg.sender == reliquary, "Only Reliquary can call this function.");
        _;
    }

    /**
     * @dev Contructor called on deployment of this contract.
     * @param _reliquary Address of Reliquary this rewarder will read state from.
     * @param _poolId ID of the pool this rewarder will read state from.
     */
    constructor(
        address _reliquary,
        uint _poolId
    ) {
        poolId = _poolId;
        reliquary = _reliquary;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Deploys a ChildRewarder contract and adds it to the childrenRewarders set.
     * @param _rewardToken Address of token rewards are distributed in.
     * @param owner Address to transfer ownership of the ChildRewarder contract to.
     * @return child Address of the new ChildRewarder.
     */
    function createChild(
        address _rewardToken,
        address owner
    ) external onlyRole(CHILD_SETTER) returns (address child) {
        child = address(new RollingRewarder(_rewardToken, reliquary, poolId));
        Ownable(child).transferOwnership(owner);
        childrenRewarders.add(child);
        emit ChildCreated(child, address(_rewardToken));
    }

    /// @notice Removes a ChildRewarder from the childrenRewarders set.
    /// @param childRewarder Address of the ChildRewarder contract to remove.
    function removeChild(
        address childRewarder
    ) external onlyRole(CHILD_SETTER) {
        require(
            childrenRewarders.remove(childRewarder),
            "That is not my child rewarder!"
        );
        emit ChildRemoved(childRewarder);
    }

    /// Call onReward function of each child.
    function onReward(
        uint relicId,
        uint rewardAmount,
        address to,
        uint oldAmount,
        uint oldLevel,
        uint newLevel
    ) external override onlyReliquary {
        uint length = childrenRewarders.length();
        for (uint i; i < length; ) {
            IRewarder(childrenRewarders.at(i)).onReward(
                relicId,
                rewardAmount,
                to,
                oldAmount,
                oldLevel,
                newLevel
            );
            unchecked {
                ++i;
            }
        }
    }

    function onDeposit(
        uint relicId,
        uint depositAmount,
        uint oldAmount,
        uint oldLevel,
        uint newLevel
    ) external override onlyReliquary {
        uint length = childrenRewarders.length();
        for (uint i; i < length; ) {
            IRewarder(childrenRewarders.at(i)).onDeposit(
                relicId,
                depositAmount,
                oldAmount,
                oldLevel,
                newLevel
            );
            unchecked {
                ++i;
            }
        }
    }

    function onWithdraw(
        uint relicId,
        uint withdrawAmount,
        uint oldAmount,
        uint oldLevel,
        uint newLevel
    ) external override onlyReliquary {
        uint length = childrenRewarders.length();
        for (uint i; i < length; ) {
            IRewarder(childrenRewarders.at(i)).onWithdraw(
                relicId,
                withdrawAmount,
                oldAmount,
                oldLevel,
                newLevel
            );
            unchecked {
                ++i;
            }
        }
    }
    
    function onSplit(
        uint fromId,
        uint newId,
        uint amount,
        uint fromAmount,
        uint level
    ) external override onlyReliquary {
        uint length = childrenRewarders.length();
        for (uint i; i < length; ) {
            IRewarder(childrenRewarders.at(i)).onSplit(
                fromId,
                newId,
                amount,
                fromAmount,
                level
            );
            unchecked {
                ++i;
            }
        }
    }

    function onShift(
        uint fromId,
        uint toId,
        uint amount,
        uint oldFromAmount,
        uint oldToAmount,
        uint fromLevel,
        uint oldToLevel,
        uint newToLevel
    ) external override onlyReliquary {
        uint length = childrenRewarders.length();
        for (uint i; i < length; ) {
            IRewarder(childrenRewarders.at(i)).onShift(
                fromId,
                toId,
                amount,
                oldFromAmount,
                oldToAmount,
                fromLevel,
                oldToLevel,
                newToLevel
            );
            unchecked {
                ++i;
            }
        }
    }

    function onMerge(
        uint fromId,
        uint toId,
        uint fromAmount,
        uint toAmount,
        uint fromLevel,
        uint oldToLevel,
        uint newToLevel
    ) external override onlyReliquary {
        uint length = childrenRewarders.length();
        for (uint i; i < length; ) {
            IRewarder(childrenRewarders.at(i)).onMerge(
                fromId,
                toId,
                fromAmount,
                toAmount,
                fromLevel,
                oldToLevel,
                newToLevel
            );
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

    function pendingTokens(
        uint relicId,
        uint rewardAmount
    )
        external
        view
        override
        returns (address[] memory rewardTokens, uint[] memory rewardAmounts)
    {
        uint length = childrenRewarders.length();
        rewardTokens = new address[](length);
        rewardAmounts = new uint[](length);

        for (uint i = 0; i < length; ) {
            RollingRewarder rewarder = RollingRewarder(
                childrenRewarders.at(i)
            );
            rewardTokens[i] = rewarder.rewardToken();
            rewardAmounts[i] = rewarder.pendingToken(relicId, rewardAmount);
            unchecked {
                ++i;
            }
        }
    }

    function setChildsRewardPool(
        address child,
        address pool
    ) external onlyRole(CHILD_SETTER) {
        RollingRewarder(child).setRewardsPool(pool);
    }
}
