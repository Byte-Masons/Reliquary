// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./Relic.sol";
import "./interfaces/IEmissionSetter.sol";
import "./interfaces/INFTDescriptor.sol";
import "./interfaces/IRewarder.sol";
import { PoolInfo, PositionInfo } from "./interfaces/IReliquary.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract ReliquaryData is Relic {
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

    function getPositionForId(uint relicId) external view returns (PositionInfo memory position) {
        position = positionForId[relicId];
    }

    function getPoolInfo(uint pid) external view returns (PoolInfo memory pool) {
        pool = poolInfo[pid];
    }
}
