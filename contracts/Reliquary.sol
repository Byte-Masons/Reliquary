// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;
pragma experimental ABIEncoderV2;

import "./Relic.sol";
import "./interfaces/IEmissionSetter.sol";
import "./interfaces/INFTDescriptor.sol";
import "./interfaces/IRewarder.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// NOTE: Work on quality of life abstractions and position management

/*
 + @title Reliquary
 + @author Justin Bebis, Zokunei & the Byte Masons team
 + @notice Built on the MasterChefV2 system authored by Sushi's team
 +
 + @notice This system is designed to modify Masterchef accounting logic such that
 + behaviors can be programmed on a per-pool basis using maturity levels. Stake in a
 + pool, also referred to as "position," is represented by means of an NFT called a
 + "Relic." Each position has a "maturity" which captures the age of the position.
 +
 + @notice Deposits are tracked by Relic ID instead of by user. This allows for
 + increased composability without affecting accounting logic too much, and users can
 + trade their Relics without withdrawing liquidity or affecting the position's maturity.
*/
contract Reliquary is Relic, AccessControlEnumerable, Multicall, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Access control roles.
    bytes32 public constant OPERATOR = keccak256("OPERATOR");

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
        uint256 amount;
        uint256 rewardDebt;
        uint256 rewardCredit;
        uint256 entry; // position owner's relative entry into the pool.
        uint256 poolId; // ensures that a single Relic is only used for one pool.
        uint256 level;
    }

    /*
     + @notice Info of each Reliquary pool
     + `accOathPerShare` Accumulated OATH per share of pool (1 / 1e12)
     + `lastRewardTime` Last timestamp the accumulated OATH was updated
     + `allocPoint` Pool's individual allocation - ratio of the total allocation
     + `levels` Array of Levels that determine how maturity affects rewards
     + `name` Name of pool to be displayed in NFT image
     + `isPair` Whether this pool's token should be displayed as a pair in NFT image
    */
    struct PoolInfo {
        uint256 accOathPerShare;
        uint256 lastRewardTime;
        uint256 allocPoint;
        Level[] levels;
        string name;
        bool isPair;
    }

    /*
     + @notice Level that determines how maturity is rewarded
     + `requiredMaturity` The minimum maturity required to reach this Level
     + `allocPoint` Level's individual allocation - ratio of the total allocation
     + `balance` Total number of tokens deposited in positions at this Level
     +
    */
    struct Level {
        uint256 requiredMaturity;
        uint256 allocPoint;
        uint256 balance;
    }

    /// @notice Address of OATH contract.
    IERC20 public immutable OATH;
    /// @notice Address of NFTDescriptor contract.
    INFTDescriptor public nftDescriptor;
    /// @notice Address of EmissionSetter contract.
    IEmissionSetter public emissionSetter;
    /// @notice Info of each Reliquary pool.
    PoolInfo[] public poolInfo;
    /// @notice Address of the LP token for each Reliquary pool.
    IERC20[] public lpToken;
    /// @notice Address of each `IRewarder` contract in Reliquary.
    IRewarder[] public rewarder;

    /// @notice Info of each staked position
    mapping(uint256 => PositionInfo) public positionForId;

    /// @notice ensures the same token isn't added to the contract twice
    mapping(address => bool) public hasBeenAdded;

    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    uint256 private constant ACC_OATH_PRECISION = 1e12;

    event Deposit(
        uint256 indexed pid,
        uint256 amount,
        address indexed to,
        uint256 indexed relicId
    );
    event Withdraw(
        uint256 indexed pid,
        uint256 amount,
        address indexed to,
        uint256 indexed relicId
    );
    event EmergencyWithdraw(
        uint256 indexed pid,
        uint256 amount,
        address indexed to,
        uint256 indexed relicId
    );
    event Harvest(
        uint256 indexed pid,
        uint256 amount,
        uint256 indexed relicId
    );
    event LogPoolAddition(
        uint256 indexed pid,
        uint256 allocPoint,
        IERC20 indexed lpToken,
        IRewarder indexed rewarder,
        Level[] levels,
        bool isPair
    );
    event LogPoolModified(
        uint256 indexed pid,
        uint256 allocPoint,
        IRewarder indexed rewarder,
        bool isPair
    );
    event LogSetNFTDescriptor(INFTDescriptor indexed nftDescriptorAddress);
    event LogSetEmissionSetter(IEmissionSetter indexed emissionSetterAddress);
    event LogUpdatePool(uint256 indexed pid, uint256 lastRewardTime, uint256 lpSupply, uint256 accOathPerShare);
    event LevelChanged(uint256 indexed relicId, uint256 newLevel);

    /*
     + @notice Constructs and initializes the contract
     + @param _oath The OATH token contract address.
     + @param _nftDescriptor The contract address for NFTDescriptor, which will return the token URI
     + @param _emissionSetter The contract address for EmissionSetter, which will return the emission rate
    */
    constructor(IERC20 _oath, INFTDescriptor _nftDescriptor, IEmissionSetter _emissionSetter) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        OATH = _oath;
        nftDescriptor = _nftDescriptor;
        emissionSetter = _emissionSetter;
    }

    function tokenURI(uint256 tokenId) public view override(ERC721) returns (string memory) {
        require(_exists(tokenId), "token does not exist");

        PositionInfo storage position = positionForId[tokenId];
        PoolInfo storage pool = poolInfo[position.poolId];
        uint256 maturity = (_timestamp() - position.entry) / 1000;

        uint256 length = pool.levels.length;
        INFTDescriptor.Level[] memory levels = new INFTDescriptor.Level[](length);
        for (uint256 i; i < length; ++i) {
            levels[i] = (
                INFTDescriptor.Level({
                    requiredMaturity: pool.levels[i].requiredMaturity,
                    allocPoint: pool.levels[i].allocPoint
                })
            );
        }

        return nftDescriptor.constructTokenURI(
            INFTDescriptor.ConstructTokenURIParams({
                tokenId: tokenId,
                poolId: position.poolId,
                isPair: pool.isPair,
                poolName: pool.name,
                underlying: address(lpToken[position.poolId]),
                amount: position.amount,
                pendingOath: pendingOath(tokenId),
                maturity: maturity,
                level: position.level,
                levels: levels
            })
        );
    }

    /// @param _nftDescriptor The contract address for NFTDescriptor, which will return the token URI
    function setNFTDescriptor(INFTDescriptor _nftDescriptor) external onlyRole(OPERATOR) {
        nftDescriptor = _nftDescriptor;
    }

    /// @param _emissionSetter The contract address for EmissionSetter, which will return the base emission rate
    function setEmissionSetter(IEmissionSetter _emissionSetter) external onlyRole(OPERATOR) {
        emissionSetter = _emissionSetter;
    }

    /// @notice Implement ERC165 to return which interfaces this contract conforms to
    function supportsInterface(bytes4 interfaceId) public view
    override(
        AccessControlEnumerable,
        ERC721Enumerable,
        IERC165
    ) returns (bool) {
        return interfaceId == type(IERC721Enumerable).interfaceId ||
            interfaceId == type(IAccessControlEnumerable).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @notice Returns the number of Reliquary pools.
    function poolLength() public view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    /*
     + @notice Add a new pool for the specified LP.
     +         Can only be called by an operator.
     +
     + @param allocPoint The allocation points for the new pool
     + @param _lpToken Address of the pooled ERC-20 token
     + @param _rewarder Address of the rewarder delegate
     + @param levels Array of Levels that determine how maturity affects rewards
     + @param name Name of pool to be displayed in NFT image
     + @param isPair Whether this pool's token should be displayed as a pair in NFT image
    */
    function addPool(
        uint256 allocPoint,
        IERC20 _lpToken,
        IRewarder _rewarder,
        Level[] memory levels,
        string memory name,
        bool isPair
    ) public onlyRole(OPERATOR) {
        require(!hasBeenAdded[address(_lpToken)], "this token has already been added");
        require(_lpToken != OATH, "same token");

        totalAllocPoint += allocPoint;
        lpToken.push(_lpToken);
        rewarder.push(_rewarder);

        poolInfo.push(
            PoolInfo({
                allocPoint: allocPoint,
                lastRewardTime: _timestamp(),
                accOathPerShare: 0,
                levels: levels,
                name: name,
                isPair: isPair
            })
        );
        hasBeenAdded[address(_lpToken)] = true;

        emit LogPoolAddition((lpToken.length - 1), allocPoint, _lpToken, _rewarder, levels, isPair);
    }

    /*
     + @notice Modify the given pool's properties.
     +         Can only be called by the owner.
     +
     + @param pid The index of the pool. See `poolInfo`.
     + @param allocPoint New AP of the pool.
     + @param _rewarder Address of the rewarder delegate.
     + @param name Name of pool to be displayed in NFT image
     + @param isPair Whether this token should be displayed as a pair in NFT image
     + @param overwriteRewarder True if _rewarder should be set. Otherwise `_rewarder` is ignored.
    */
    function modifyPool(
        uint256 pid,
        uint256 allocPoint,
        IRewarder _rewarder,
        string memory name,
        bool isPair,
        bool overwriteRewarder
    ) public onlyRole(OPERATOR) {
        require(pid < poolInfo.length, "set: pool does not exist");

        PoolInfo storage pool = poolInfo[pid];
        totalAllocPoint -= pool.allocPoint;
        totalAllocPoint += allocPoint;
        pool.allocPoint = allocPoint;

        if (overwriteRewarder) {
            rewarder[pid] = _rewarder;
        }

        pool.name = name;
        pool.isPair = isPair;

        emit LogPoolModified(pid, allocPoint, overwriteRewarder ? _rewarder : rewarder[pid], isPair);
    }

    /*
     + @notice View function to see pending OATH on frontend.
     + @param relicId ID of the position.
     + @return pending OATH reward for a given position owner.
    */
    function pendingOath(uint256 relicId) public view returns (uint256 pending) {
        _ensureValidPosition(relicId);

        PositionInfo storage position = positionForId[relicId];
        PoolInfo storage pool = poolInfo[position.poolId];
        uint256 accOathPerShare = pool.accOathPerShare;
        uint256 lpSupply = _poolBalance(position.poolId);

        uint256 millisSinceReward = _timestamp() - pool.lastRewardTime;
        if (millisSinceReward != 0 && lpSupply != 0) {
            uint256 oathReward = (millisSinceReward * _baseEmissionsPerMillisecond() * pool.allocPoint) / totalAllocPoint;
            accOathPerShare += (oathReward * ACC_OATH_PRECISION) / lpSupply;
        }

        uint256 leveledAmount = position.amount * pool.levels[position.level].allocPoint;
        pending = leveledAmount * accOathPerShare / ACC_OATH_PRECISION + position.rewardCredit - position.rewardDebt;
    }

    /*
     + @notice Update reward variables for all pools. Be careful of gas spending!
     + @param pids Pool IDs of all to be updated. Make sure to update all active pools.
    */
    function massUpdatePools(uint256[] calldata pids) external nonReentrant {
        for (uint256 i = 0; i < pids.length; i++) {
            _updatePool(pids[i]);
        }
    }

    /*
     + @notice Update reward variables of the given pool.
     + @param pid The index of the pool. See `poolInfo`.
     + @return pool Returns the pool that was updated.
    */
    function updatePool(uint256 pid) external nonReentrant {
        _updatePool(pid);
    }

    /// @dev Internal updatePool function without nonReentrant modifier
    function _updatePool(uint256 pid) internal {
        require(pid < poolLength());
        PoolInfo storage pool = poolInfo[pid];
        uint256 millisSinceReward = _timestamp() - pool.lastRewardTime;

        if (millisSinceReward != 0) {
            uint256 lpSupply = _poolBalance(pid);

            if (lpSupply != 0) {
                uint256 oathReward = (millisSinceReward * _baseEmissionsPerMillisecond() * pool.allocPoint) /
                    totalAllocPoint;
                pool.accOathPerShare += (oathReward * ACC_OATH_PRECISION) / lpSupply;
            }

            pool.lastRewardTime = _timestamp();

            emit LogUpdatePool(pid, pool.lastRewardTime, lpSupply, pool.accOathPerShare);
        }
    }

    /*
     + @notice Create a new Relic NFT and deposit into this position
     + @param to Address to mint the Relic to
     + @param pid The index of the pool. See `poolInfo`.
     + @param amount Token amount to deposit.
    */
    function createRelicAndDeposit(
        address to,
        uint256 pid,
        uint256 amount
    ) public nonReentrant returns (uint256 id) {
        require(pid < poolInfo.length, "invalid pool ID");
        id = mint(to);
        positionForId[id].poolId = pid;
        _deposit(amount, id);
    }

    /*
     + @notice Deposit LP tokens to Reliquary for OATH allocation.
     + @param amount Token amount to deposit.
     + @param relicId NFT ID of the receiver of `amount` deposit benefit.
    */
    function deposit(uint256 amount, uint256 relicId) external nonReentrant {
        _ensureValidPosition(relicId);
        require(ownerOf(relicId) == msg.sender, "you do not own this position");
        _deposit(amount, relicId);
    }

    /// @dev Internal deposit function that assumes relicId is valid.
    function _deposit(uint256 amount, uint256 relicId) internal {
        require(amount != 0, "depositing 0 amount");

        PositionInfo storage position = positionForId[relicId];
        _updatePool(position.poolId);
        _updateEntry(amount, relicId);

        uint256 oldAmount = position.amount;
        uint256 newAmount = oldAmount + amount;
        position.amount = newAmount;
        uint256 oldLevel = position.level;
        uint256 newLevel = _updateLevel(relicId);
        PoolInfo storage pool = poolInfo[position.poolId];
        if (oldLevel != newLevel) {
            pool.levels[oldLevel].balance -= oldAmount;
            pool.levels[newLevel].balance += newAmount;
        } else {
            pool.levels[oldLevel].balance += amount;
        }

        uint256 leveledAmount = oldAmount * pool.levels[oldLevel].allocPoint;
        uint256 accumulatedOath = leveledAmount * pool.accOathPerShare / ACC_OATH_PRECISION;
        uint256 _pendingOath = accumulatedOath - position.rewardDebt;

        position.rewardDebt = newAmount * pool.levels[newLevel].allocPoint * pool.accOathPerShare / ACC_OATH_PRECISION;

        if (_pendingOath != 0) {
            position.rewardCredit += _pendingOath;
        }

        address to = ownerOf(relicId);
        IRewarder _rewarder = rewarder[position.poolId];
        if (address(_rewarder) != address(0)) {
            _rewarder.onOathReward(position.poolId, to, to, 0, position.amount);
        }

        lpToken[position.poolId].safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(position.poolId, amount, to, relicId);
    }

    /*
     + @notice Withdraw LP tokens.
     + @param amount token amount to withdraw.
     + @param relicId NFT ID of the receiver of the tokens and OATH rewards.
    */
    function withdraw(uint256 amount, uint256 relicId) public nonReentrant {
        _ensureValidPosition(relicId);
        address to = ownerOf(relicId);
        require(to == msg.sender, "you do not own this position");
        require(amount != 0, "withdrawing 0 amount");

        PositionInfo storage position = positionForId[relicId];
        _updatePool(position.poolId);

        uint256 oldAmount = position.amount;
        uint256 newAmount = oldAmount - amount;
        position.amount = newAmount;
        _updateEntry(amount, relicId);
        uint256 oldLevel = position.level;
        uint256 newLevel = _updateLevel(relicId);
        PoolInfo storage pool = poolInfo[position.poolId];
        if (oldLevel != newLevel) {
            pool.levels[oldLevel].balance -= oldAmount;
            pool.levels[newLevel].balance += newAmount;
        } else {
            pool.levels[oldLevel].balance -= amount;
        }

        uint256 leveledAmount = oldAmount * pool.levels[oldLevel].allocPoint;
        uint256 accumulatedOath = leveledAmount * pool.accOathPerShare / ACC_OATH_PRECISION;
        uint256 _pendingOath = accumulatedOath - position.rewardDebt;

        position.rewardDebt = newAmount * pool.levels[newLevel].allocPoint * pool.accOathPerShare / ACC_OATH_PRECISION;

        if (_pendingOath != 0) {
            position.rewardCredit += _pendingOath;
        }

        IRewarder _rewarder = rewarder[position.poolId];
        if (address(_rewarder) != address(0)) {
            _rewarder.onOathReward(position.poolId, msg.sender, to, _pendingOath, position.amount);
        }

        lpToken[position.poolId].safeTransfer(to, amount);
        if (newAmount == 0) {
            burn(relicId);
            delete (positionForId[relicId]);
        }

        emit Withdraw(position.poolId, amount, to, relicId);
    }

    /*
     + @notice Harvest proceeds for transaction sender to owner of `relicId`.
     + @param relicId NFT ID of the receiver of OATH rewards.
    */
    function harvest(uint256 relicId) public nonReentrant {
        _ensureValidPosition(relicId);
        address to = ownerOf(relicId);
        require(to == msg.sender, "you do not own this position");

        PositionInfo storage position = positionForId[relicId];
        _updatePool(position.poolId);

        // Effects
        uint256 amount = position.amount;
        uint256 oldLevel = position.level;
        uint256 newLevel = _updateLevel(relicId);
        PoolInfo storage pool = poolInfo[position.poolId];
        if (oldLevel != newLevel) {
            pool.levels[oldLevel].balance -= amount;
            pool.levels[newLevel].balance += amount;
        }

        uint256 leveledAmount = amount * pool.levels[oldLevel].allocPoint;
        uint256 accumulatedOath = leveledAmount * pool.accOathPerShare / ACC_OATH_PRECISION;
        uint256 rewardCredit = position.rewardCredit;
        uint256 _pendingOath = accumulatedOath + rewardCredit - position.rewardDebt;
        if (rewardCredit != 0) {
            position.rewardCredit = 0;
        }

        position.rewardDebt = amount * pool.levels[newLevel].allocPoint * pool.accOathPerShare / ACC_OATH_PRECISION;

        // Interactions
        if (_pendingOath != 0) {
            OATH.safeTransfer(to, _pendingOath);
        }

        IRewarder _rewarder = rewarder[position.poolId];
        if (address(_rewarder) != address(0)) {
            _rewarder.onOathReward(position.poolId, msg.sender, to, _pendingOath, position.amount);
        }

        emit Harvest(position.poolId, _pendingOath, relicId);
    }

    /*
     + @notice Withdraw LP tokens and harvest proceeds for transaction sender to owner of `relicId`.
     + @param amount token amount to withdraw.
     + @param relicId NFT ID of the receiver of the tokens and OATH rewards.
    */
    function withdrawAndHarvest(uint256 amount, uint256 relicId) public nonReentrant {
        _ensureValidPosition(relicId);
        address to = ownerOf(relicId);
        require(to == msg.sender, "you do not own this position");
        require(amount != 0, "withdrawing 0 amount");

        PositionInfo storage position = positionForId[relicId];
        _updatePool(position.poolId);

        uint256 oldAmount = position.amount;
        uint256 newAmount = oldAmount - amount;
        position.amount = newAmount;
        _updateEntry(amount, relicId);
        uint256 oldLevel = position.level;
        uint256 newLevel = _updateLevel(relicId);
        PoolInfo storage pool = poolInfo[position.poolId];
        if (oldLevel != newLevel) {
            pool.levels[oldLevel].balance -= oldAmount;
            pool.levels[newLevel].balance += newAmount;
        } else {
            pool.levels[oldLevel].balance -= amount;
        }

        uint256 leveledAmount = oldAmount * pool.levels[oldLevel].allocPoint;
        uint256 accumulatedOath = leveledAmount * pool.accOathPerShare / ACC_OATH_PRECISION;
        uint256 rewardCredit = position.rewardCredit;
        uint256 _pendingOath = accumulatedOath + rewardCredit - position.rewardDebt;
        if (rewardCredit != 0) {
            position.rewardCredit = 0;
        }

        position.rewardDebt = newAmount * pool.levels[newLevel].allocPoint * pool.accOathPerShare / ACC_OATH_PRECISION;

        if (_pendingOath != 0) {
            OATH.safeTransfer(to, _pendingOath);
        }

        IRewarder _rewarder = rewarder[position.poolId];
        if (address(_rewarder) != address(0)) {
            _rewarder.onOathReward(position.poolId, msg.sender, to, _pendingOath, position.amount);
        }

        lpToken[position.poolId].safeTransfer(to, amount);
        if (position.amount == 0) {
            burn(relicId);
            delete (positionForId[relicId]);
        }

        emit Withdraw(position.poolId, amount, to, relicId);
        emit Harvest(position.poolId, _pendingOath, relicId);
    }

    /*
     + @notice Withdraw without caring about rewards. EMERGENCY ONLY.
     + @param relicId NFT ID of the receiver of the tokens.
    */
    function emergencyWithdraw(uint256 relicId) public nonReentrant {
        _ensureValidPosition(relicId);
        address to = ownerOf(relicId);
        require(to == msg.sender, "you do not own this position");

        PositionInfo storage position = positionForId[relicId];
        uint256 amount = position.amount;
        PoolInfo storage pool = poolInfo[position.poolId];

        position.amount = 0;
        position.rewardDebt = 0;
        _updateEntry(amount, relicId);
        pool.levels[position.level].balance -= amount;
        _updateLevel(relicId);

        IRewarder _rewarder = rewarder[position.poolId];
        if (address(_rewarder) != address(0)) {
            _rewarder.onOathReward(position.poolId, msg.sender, to, 0, 0);
        }

        // Note: transfer can fail or succeed if `amount` is zero.
        lpToken[position.poolId].safeTransfer(to, amount);
        burn(relicId);
        delete (positionForId[relicId]);

        emit EmergencyWithdraw(position.poolId, amount, to, relicId);
    }

    /// @notice Gets the base emission rate from external, upgradable contract
    function _baseEmissionsPerMillisecond() internal view returns (uint256 rate) {
        rate = emissionSetter.getRate();
    }

    /*
     + @notice Utility function to find weights without any underflows or zero division problems.
     + @param addedValue New value being added
     + @param oldValue Current amount of x
    */
    function _findWeight(
      uint addedValue,
      uint oldValue
    ) public pure returns (uint256 weightNew) {
      if (oldValue == 0) {
        weightNew = 1e18;
      } else {
        if (addedValue < oldValue) {
          weightNew = addedValue * 1e18 / (addedValue + oldValue);
        } else if (oldValue < addedValue) {
          uint256 weightOld = oldValue * 1e18 / (addedValue + oldValue);
          weightNew = 1e18 - weightOld;
        } else {
          weightNew = 1e18 / 2;
        }
      }
    }

    /*
     + @notice Updates the user's entry time based on the weight of their deposit or withdrawal
     + @param amount The amount of the deposit / withdrawal
     + @param relicId The NFT ID of the position being updated
    */
    function _updateEntry(uint256 amount, uint256 relicId) internal {
        PositionInfo storage position = positionForId[relicId];
        uint256 weight = _findWeight(amount, position.amount);
        uint256 maturity = _timestamp() - position.entry;
        position.entry += maturity * weight / 1e18;
    }

    /*
     + @notice Updates the position's level based on entry time
     + @param relicId The NFT ID of the position being updated
    */
    function _updateLevel(uint256 relicId) internal returns (uint256 newLevel) {
        PositionInfo storage position = positionForId[relicId];
        PoolInfo storage pool = poolInfo[position.poolId];
        uint256 maturity = (_timestamp() - position.entry) / 1000;
        for (uint256 i = pool.levels.length - 1; i >= 0; --i) {
            if (maturity >= pool.levels[i].requiredMaturity) {
                if (position.level != i) {
                    position.level = i;
                    emit LevelChanged(relicId, newLevel);
                }
                newLevel = i;
                break;
            }
        }
    }

    /*
     + @notice returns The total deposits of the pool's token
     + @param pid The index of the pool. See `poolInfo`.
     + @return The amount of pool tokens held by the contract
    */
    function _poolBalance(uint256 pid) internal view returns (uint256 total) {
        PoolInfo storage pool = poolInfo[pid];
        uint256 length = pool.levels.length;
        for (uint256 i; i < length; ++i) {
            total += pool.levels[i].balance * pool.levels[i].allocPoint;
        }
    }

    /// @dev Converts timestamp to milliseconds so precision isn't lost when we mutate the
    /// user's entry time.
    function _timestamp() internal view returns (uint256 timestamp) {
        timestamp = block.timestamp * 1000;
    }

    /// @notice Existing position is valid if and only if it has non-zero amount.
    function _ensureValidPosition(uint256 relicId) internal view {
        PositionInfo storage position = positionForId[relicId];
        require(position.amount != 0, "invalid position ID");
    }
}
