// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./Relic.sol";
import "./interfaces/IEmissionSetter.sol";
import "./interfaces/INFTDescriptor.sol";
import "./interfaces/IRewarder.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract ReliquaryData is Relic {
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

    /// @notice Address of OATH contract.
    IERC20 public immutable OATH;
    /// @notice Address of each NFTDescriptor contract.
    INFTDescriptor[] public nftDescriptor;
    /// @notice Address of EmissionSetter contract.
    IEmissionSetter public emissionSetter;
    /// @notice Info of each Reliquary pool.
    PoolInfo[] public poolInfo;
    /// @notice Address of the LP token for each Reliquary pool.
    IERC20[] public lpToken;
    /// @notice Address of each `IRewarder` contract.
    IRewarder[] public rewarder;

    /// @notice Info of each staked position
    mapping(uint => PositionInfo) public positionForId;

    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint public totalAllocPoint;

    /*
     + @notice Constructs and initializes the contract
     + @param _oath The OATH token contract address.
     + @param _nftDescriptor The contract address for NFTDescriptor, which will return the token URI
     + @param _emissionSetter The contract address for EmissionSetter, which will return the emission rate
    */
    constructor(IERC20 _oath, IEmissionSetter _emissionSetter) {
        OATH = _oath;
        emissionSetter = _emissionSetter;
    }

    /// @notice Returns the number of Reliquary pools.
    function poolLength() public view returns (uint pools) {
        pools = poolInfo.length;
    }

    /*
     + @notice View function to see pending OATH on frontend.
     + @param relicId ID of the position.
     + @return pending OATH reward for a given position owner.
    */
    function pendingOath(uint relicId) external view virtual returns (uint pending);

    function levels(uint pid) external view returns (Level[] memory _levels) {
        _levels = poolInfo[pid].levels;
    }
}
