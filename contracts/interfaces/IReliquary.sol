// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "contracts/interfaces/ICurves.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

/// @dev Level of precision rewards are calculated to.
uint256 constant WEIGHT_PRECISION = 1e18;
/// @dev Level of precision rewards are calculated to.
uint256 constant ACC_REWARD_PRECISION = 1e41;
/// @dev Max supply allowed for checks purpose.
uint256 constant MAX_SUPPLY_ALLOWED = 100e9 ether;

/// @dev Indicates whether tokens are being added to, or removed from, a pool.
enum Kind {
    DEPOSIT,
    WITHDRAW,
    UPDATE
}

/**
 * @notice Info for each Reliquary position.
 * @dev 3 storage slots
 * `rewardDebt` Amount of reward token accumalated before the position's entry or last harvest.
 * `rewardCredit` Amount of reward token owed to the user on next harvest.
 * `amount` LP token amount the position owner has provided.
 * `entry` Used to determine the maturity of the position, position owner's relative entry into the pool.
 * `level` Index of this position's level within the pool's array of levels, ensures that a single Relic is only used for one pool.
 * `poolId` ID of the pool to which this position belongs.
 */
struct PositionInfo {
    uint256 rewardDebt;
    uint256 rewardCredit;
    uint128 amount;
    uint40 entry;
    uint40 level;
    uint8 poolId;
}

/**
 * @notice Info of each Reliquary pool.
 * @dev 7 storage slots
 * `name` Name of pool to be displayed in NFT image.
 * `accRewardPerShare` Accumulated reward tokens per share of pool (1 / WEIGHT_PRECISION).
 * `totalLpSupplied` Total number of LPs in the pool.
 * `nftDescriptor` The nft descriptor address.
 * `rewarder` The nft rewarder address.
 * `poolToken` ERC20 token supplied.
 * `lastRewardTime` Last timestamp the accumulated reward was updated.
 * `allowPartialWithdrawals` Whether users can withdraw less than their entire position.
 * `allocPoint` Pool's individual allocation - ratio of the total allocation.
 * `curve` Contract that define the function: f(maturity) = multiplier.
 *     A value of false will also disable shift and split functionality.
 */
struct PoolInfo {
    string name;
    uint256 accRewardPerShare;
    uint256 totalLpSupplied;
    address nftDescriptor;
    address rewarder;
    address poolToken;
    uint40 lastRewardTime;
    bool allowPartialWithdrawals;
    uint96 allocPoint;
    ICurves curve;
}

interface IReliquary is IERC721 {
    // Errors
    error Reliquary__BURNING_PRINCIPAL();
    error Reliquary__BURNING_REWARDS();
    error Reliquary__REWARD_TOKEN_AS_POOL_TOKEN();
    error Reliquary__TOKEN_NOT_COMPATIBLE();
    error Reliquary__ZERO_TOTAL_ALLOC_POINT();
    error Reliquary__NON_EXISTENT_POOL();
    error Reliquary__ZERO_INPUT();
    error Reliquary__NOT_OWNER();
    error Reliquary__DUPLICATE_RELIC_IDS();
    error Reliquary__RELICS_NOT_OF_SAME_POOL();
    error Reliquary__MERGING_EMPTY_RELICS();
    error Reliquary__NOT_APPROVED_OR_OWNER();
    error Reliquary__PARTIAL_WITHDRAWALS_DISABLED();
    error Reliquary__MULTIPLIER_AT_MATURITY_ZERO_SHOULD_BE_GT_ZERO();
    error Reliquary__REWARD_PRECISION_ISSUE();

    function setEmissionRate(uint256 _emissionRate) external;

    function addPool(
        uint256 _allocPoint,
        address _poolToken,
        address _rewarder,
        ICurves _curve,
        string memory _name,
        address _nftDescriptor,
        bool _allowPartialWithdrawals
    ) external;

    function modifyPool(
        uint8 _poolId,
        uint256 _allocPoint,
        address _rewarder,
        string calldata _name,
        address _nftDescriptor,
        bool _overwriteRewarder
    ) external;

    function massUpdatePools() external;

    function updatePool(uint8 _poolId) external;

    function deposit(uint256 _amount, uint256 _relicId, address _harvestTo) external;

    function withdraw(uint256 _amount, uint256 _relicId, address _harvestTo) external;

    function update(uint256 _relicId, address _harvestTo) external;

    function emergencyWithdraw(uint256 _relicId) external;

    function poolLength() external view returns (uint256 pools_);

    function getPositionForId(uint256 _posId) external view returns (PositionInfo memory);

    function getPoolInfo(uint8 _poolId) external view returns (PoolInfo memory);

    function getTotalLpSupplied(uint8 _poolId) external view returns (uint256 lp_);

    function isApprovedOrOwner(address, uint256) external view returns (bool);

    function createRelicAndDeposit(address _to, uint8 _poolId, uint256 _amount)
        external
        returns (uint256 _id_);

    function split(uint256 _relicId, uint256 _amount, address _to)
        external
        returns (uint256 newId_);

    function shift(uint256 _fromId, uint256 _toId, uint256 _amount) external;

    function merge(uint256 _fromId, uint256 _toId) external;

    function burn(uint256 _tokenId) external;

    function pendingReward(uint256 _relicId) external view returns (uint256 pending_);

    function rewardToken() external view returns (address);

    function emissionRate() external view returns (uint256);

    function totalAllocPoint() external view returns (uint256);
}
