// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "./IEmissionCurve.sol";
import "./INFTDescriptor.sol";
import "./IRewarder.sol";

/*
 + @notice Info for each Reliquary position.
 + `amount` LP token amount the position owner has provided
 + `rewardDebt` Amount of reward token accumalated before the position's entry or last harvest
 + `rewardCredit` Amount of reward token owed to the user on next harvest
 + `entry` Used to determine the maturity of the position
 + `poolId` ID of the pool to which this position belongs
 + `level` Index of this position's level within the pool's array of levels
 + `genesis` Relic creation time
 + `lastMaturityBonus` Last time the position had its entry altered by a MaturityModifier
*/
struct PositionInfo {
    uint amount;
    uint rewardDebt;
    uint rewardCredit;
    uint entry; // position owner's relative entry into the pool.
    uint poolId; // ensures that a single Relic is only used for one pool.
    uint level;
    uint genesis;
    uint lastMaturityBonus;
}

/*
 + @notice Info of each Reliquary pool
 + `accRewardPerShare` Accumulated reward tokens per share of pool (1 / 1e12)
 + `lastRewardTime` Last timestamp the accumulated reward was updated
 + `allocPoint` Pool's individual allocation - ratio of the total allocation
 + `name` Name of pool to be displayed in NFT image
*/
struct PoolInfo {
    uint accRewardPerShare;
    uint lastRewardTime;
    uint allocPoint;
    string name;
}

/*
 + @notice Level that determines how maturity is rewarded
 + `requiredMaturity` The minimum maturity (in seconds) required to reach this Level
 + `allocPoint` Level's individual allocation - ratio of the total allocation
 + `balance` Total number of tokens deposited in positions at this Level
*/
struct LevelInfo {
    uint[] requiredMaturity;
    uint[] allocPoint;
    uint[] balance;
}

/*
 + @notice Object representing pending rewards and related data for a position.
 + `relicId` The NFT ID of the given position.
 + `poolId` ID of the pool to which this position belongs.
 + `pendingReward` pending reward amount for a given position.
*/
struct PendingReward {
    uint relicId;
    uint poolId;
    uint pendingReward;
}

interface IReliquary is IERC721Enumerable {

  function burn(uint tokenId) external;
  function setEmissionCurve(IEmissionCurve _emissionCurve) external;
  function supportsInterface(bytes4 interfaceId) external view returns (bool);
  function addPool(
        uint allocPoint,
        IERC20 _poolToken,
        IRewarder _rewarder,
        uint[] calldata requiredMaturity,
        uint[] calldata allocPoints,
        string memory name,
        INFTDescriptor _nftDescriptor
    ) external;
  function modifyPool(
        uint pid,
        uint allocPoint,
        IRewarder _rewarder,
        string calldata name,
        INFTDescriptor _nftDescriptor,
        bool overwriteRewarder
    ) external;
  function modifyMaturity(uint relicId, uint points) external returns (uint receivedBonus);
  function updateLastMaturityBonus(uint relicId) external;
  function pendingReward(uint relicId) external view returns (uint pending);
  function pendingRewardsOfOwner(address owner) external view returns (PendingReward[] memory pendingRewards);
  function relicPositionsOfOwner(
      address owner
    ) external view returns (uint[] memory relicIds, PositionInfo[] memory positionInfos);
  function levelOnUpdate(uint relicId) external view returns (uint level);
  function massUpdatePools(uint[] calldata pids) external;
  function updatePool(uint pid) external;
  function createRelicAndDeposit(
        address to,
        uint pid,
        uint amount
    ) external returns (uint id);
  function deposit(uint amount, uint relicId) external;
  function withdraw(uint amount, uint relicId) external;
  function harvest(uint relicId, address harvestTo) external;
  function withdrawAndHarvest(uint amount, uint relicId, address harvestTo) external;
  function emergencyWithdraw(uint relicId) external;
  function updatePosition(uint relicId) external;
  function split(uint relicId, uint amount, address to) external returns (uint newId);
  function shift(uint fromId, uint toId, uint amount) external;
  function merge(uint fromId, uint toId) external;

  // State

  function rewardToken() external view returns (IERC20);
  function nftDescriptor(uint) external view returns (INFTDescriptor);
  function emissionCurve() external view returns (IEmissionCurve);
  function getPoolInfo(uint) external view returns (PoolInfo memory);
  function getLevelInfo(uint) external view returns (LevelInfo memory);
  function poolToken(uint) external view returns (IERC20);
  function rewarder(uint) external view returns (IRewarder);

  function getPositionForId(uint) external view returns (PositionInfo memory);
  function totalAllocPoint() external view returns (uint);
  function poolLength() external view returns (uint);
  function isApprovedOrOwner(address, uint) external view returns (bool);

}
