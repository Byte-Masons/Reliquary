// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "./IEmissionSetter.sol";
import "./INFTDescriptor.sol";
import "./IRewarder.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/*
 + @notice Level that determines how maturity is rewarded
 + `requiredMaturity` The minimum maturity (in seconds) required to reach this Level
 + `allocPoint` Level's individual allocation - ratio of the total allocation
 + `balance` Total number of tokens deposited in positions at this Level
*/
struct Level {
    uint requiredMaturity;
    uint allocPoint;
    uint balance;
}

/*
 + @notice Info for each Reliquary position.
 + `amount` LP token amount the position owner has provided
 + `rewardDebt` OATH accumalated before the position's entry or last harvest
 + `rewardCredit` OATH owed to the user on next harvest
 + `entry` Used to determine the maturity of the position
 + `poolId` ID of the pool to which this position belongs
 + `level` Index of this position's level within the pool's array of levels
*/
struct PositionInfo {
    uint amount;
    uint rewardDebt;
    uint rewardCredit;
    uint entry; // position owner's relative entry into the pool.
    uint poolId; // ensures that a single Relic is only used for one pool.
    uint level;
}

/*
 + @notice Info of each Reliquary pool
 + `accOathPerShare` Accumulated OATH per share of pool (1 / 1e12)
 + `lastRewardTime` Last timestamp the accumulated OATH was updated
 + `allocPoint` Pool's individual allocation - ratio of the total allocation
 + `levels` Array of Levels that determine how maturity affects rewards
 + `name` Name of pool to be displayed in NFT image
*/
struct PoolInfo {
    uint accOathPerShare;
    uint lastRewardTime;
    uint allocPoint;
    Level[] levels;
    string name;
}

interface IReliquary is IERC721Enumerable {

  function setEmissionSetter(IEmissionSetter _emissionSetter) external;
  function supportsInterface(bytes4 interfaceId) external view returns (bool);
  function addPool(
        uint allocPoint,
        IERC20 _lpToken,
        IRewarder _rewarder,
        Level[] calldata levels,
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
  function pendingOath(uint relicId) external view returns (uint pending);
  function massUpdatePools(uint[] calldata pids) external;
  function updatePool(uint pid) external;
  function createRelicAndDeposit(
        address to,
        uint pid,
        uint amount
    ) external returns (uint id);
  function deposit(uint amount, uint relicId) external;
  function withdraw(uint amount, uint relicId) external;
  function harvest(uint relicId) external;
  function withdrawAndHarvest(uint amount, uint relicId) external;
  function emergencyWithdraw(uint relicId) external;
  function updatePosition(uint relicId) external;

  // State

  function OATH() external view returns (IERC20);
  function nftDescriptor(uint) external view returns (INFTDescriptor);
  function emissionSetter() external view returns (IEmissionSetter);
  function getPoolInfo(uint) external view returns (PoolInfo memory);
  function lpToken(uint) external view returns (IERC20);
  function rewarder(uint) external view returns (IRewarder);

  function getPositionForId(uint) external view returns (PositionInfo memory);
  function totalAllocPoint() external view returns (uint);
  function poolLength() external view returns (uint);

}
