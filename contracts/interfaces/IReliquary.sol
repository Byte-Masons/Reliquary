// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

/**
 * @notice Info for each Reliquary position.
 * `amount` LP token amount the position owner has provided.
 * `rewardDebt` Amount of reward token accumalated before the position's entry or last harvest.
 * `rewardCredit` Amount of reward token owed to the user on next harvest.
 * `entry` Used to determine the maturity of the position.
 * `poolId` ID of the pool to which this position belongs.
 * `level` Index of this position's level within the pool's array of levels.
 */
struct PositionInfo {
    uint amount;
    uint rewardDebt;
    uint rewardCredit;
    uint entry; // position owner's relative entry into the pool.
    uint poolId; // ensures that a single Relic is only used for one pool.
    uint level;
}

/**
 * @notice Info of each Reliquary pool.
 * `accRewardPerShare` Accumulated reward tokens per share of pool (1 / 1e12).
 * `lastRewardTime` Last timestamp the accumulated reward was updated.
 * `allocPoint` Pool's individual allocation - ratio of the total allocation.
 * `name` Name of pool to be displayed in NFT image.
 * `allowPartialWithdrawals` Whether users can withdraw less than their entire position.
 *     A value of false will also disable shift and split functionality.
 */
struct PoolInfo {
    uint accRewardPerShare;
    uint lastRewardTime;
    uint allocPoint;
    string name;
    bool allowPartialWithdrawals;
}

/**
 * @notice Info for each level in a pool that determines how maturity is rewarded.
 * `requiredMaturities` The minimum maturity (in seconds) required to reach each Level.
 * `multipliers` Multiplier for each level applied to amount of incentivized token when calculating rewards in the pool.
 *     This is applied to both the numerator and denominator in the calculation such that the size of a user's position
 *     is effectively considered to be the actual number of tokens times the multiplier for their level.
 *     Also note that these multipliers do not affect the overall emission rate.
 * `balance` Total (actual) number of tokens deposited in positions at each level.
 */
struct LevelInfo {
    uint[] requiredMaturities;
    uint[] multipliers;
    uint[] balance;
}

/**
 * @notice Object representing pending rewards and related data for a position.
 * `relicId` The NFT ID of the given position.
 * `poolId` ID of the pool to which this position belongs.
 * `pendingReward` pending reward amount for a given position.
 */
struct PendingReward {
    uint relicId;
    uint poolId;
    uint pendingReward;
}

interface IReliquary is IERC721Enumerable {
    function setEmissionCurve(address _emissionCurve) external;
    function addPool(
        uint allocPoint,
        address _poolToken,
        address _rewarder,
        uint[] calldata requiredMaturity,
        uint[] calldata allocPoints,
        string memory name,
        address _nftDescriptor,
        bool allowPartialWithdrawals
    ) external;
    function modifyPool(
        uint pid,
        uint allocPoint,
        address _rewarder,
        string calldata name,
        address _nftDescriptor,
        bool overwriteRewarder
    ) external;
    function massUpdatePools(uint[] calldata pids) external;
    function updatePool(uint pid) external;
    function deposit(uint amount, uint relicId) external;
    function withdraw(uint amount, uint relicId) external;
    function harvest(uint relicId, address harvestTo) external;
    function withdrawAndHarvest(uint amount, uint relicId, address harvestTo) external;
    function emergencyWithdraw(uint relicId) external;
    function updatePosition(uint relicId) external;
    function getPositionForId(uint) external view returns (PositionInfo memory);
    function getPoolInfo(uint) external view returns (PoolInfo memory);
    function getLevelInfo(uint) external view returns (LevelInfo memory);
    function pendingRewardsOfOwner(address owner) external view returns (PendingReward[] memory pendingRewards);
    function relicPositionsOfOwner(address owner)
        external
        view
        returns (uint[] memory relicIds, PositionInfo[] memory positionInfos);
    function isApprovedOrOwner(address, uint) external view returns (bool);
    function createRelicAndDeposit(address to, uint pid, uint amount) external returns (uint id);
    function split(uint relicId, uint amount, address to) external returns (uint newId);
    function shift(uint fromId, uint toId, uint amount) external;
    function merge(uint fromId, uint toId) external;
    function burn(uint tokenId) external;
    function pendingReward(uint relicId) external view returns (uint pending);
    function levelOnUpdate(uint relicId) external view returns (uint level);
    function poolLength() external view returns (uint);

    function rewardToken() external view returns (address);
    function nftDescriptor(uint) external view returns (address);
    function emissionCurve() external view returns (address);
    function poolToken(uint) external view returns (address);
    function rewarder(uint) external view returns (address);
    function totalAllocPoint() external view returns (uint);
}
