// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./ReliquaryData.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

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
contract Reliquary is ReliquaryData, AccessControlEnumerable, Multicall, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Access control roles.
    bytes32 public constant OPERATOR = keccak256("OPERATOR");

    /// @notice Indicates whether tokens are being added to, or removed from, a pool
    enum Kind {
        DEPOSIT,
        WITHDRAW,
        OTHER
    }

    uint private constant ACC_OATH_PRECISION = 1e12;

    event Deposit(
        uint indexed pid,
        uint amount,
        address indexed to,
        uint indexed relicId
    );
    event Withdraw(
        uint indexed pid,
        uint amount,
        address indexed to,
        uint indexed relicId
    );
    event EmergencyWithdraw(
        uint indexed pid,
        uint amount,
        address indexed to,
        uint indexed relicId
    );
    event Harvest(
        uint indexed pid,
        uint amount,
        uint indexed relicId
    );
    event LogPoolAddition(
        uint indexed pid,
        uint allocPoint,
        IERC20 indexed lpToken,
        IRewarder indexed rewarder,
        Level[] levels,
        INFTDescriptor nftDescriptor
    );
    event LogPoolModified(
        uint indexed pid,
        uint allocPoint,
        IRewarder indexed rewarder,
        INFTDescriptor nftDescriptor
    );
    event LogSetEmissionSetter(IEmissionSetter indexed emissionSetterAddress);
    event LogUpdatePool(uint indexed pid, uint lastRewardTime, uint lpSupply, uint accOathPerShare);
    event LevelChanged(uint indexed relicId, uint newLevel);

    /*
     + @notice Constructs and initializes the contract
     + @param _oath The OATH token contract address.
     + @param _emissionSetter The contract address for EmissionSetter, which will return the emission rate
    */
    constructor(
        IERC20 _oath,
        IEmissionSetter _emissionSetter
    ) ReliquaryData(_oath, _emissionSetter) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function tokenURI(uint tokenId) public view override(ERC721) returns (string memory) {
        require(_exists(tokenId), "token does not exist");

        return nftDescriptor[positionForId[tokenId].poolId].constructTokenURI(tokenId);
    }

    /// @param _emissionSetter The contract address for EmissionSetter, which will return the base emission rate
    function setEmissionSetter(IEmissionSetter _emissionSetter) external onlyRole(OPERATOR) {
        emissionSetter = _emissionSetter;
        emit LogSetEmissionSetter(_emissionSetter);
    }

    /// @notice Implement ERC165 to return which interfaces this contract conforms to
    function supportsInterface(bytes4 interfaceId) public view
    override(
        AccessControlEnumerable,
        ERC721Enumerable
    ) returns (bool) {
        return interfaceId == type(IERC721Enumerable).interfaceId ||
            interfaceId == type(IAccessControlEnumerable).interfaceId ||
            super.supportsInterface(interfaceId);
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
     + @param _nftDescriptor The contract address for NFTDescriptor, which will return the token URI
    */
    function addPool(
        uint allocPoint,
        IERC20 _lpToken,
        IRewarder _rewarder,
        Level[] calldata levels,
        string memory name,
        INFTDescriptor _nftDescriptor
    ) external onlyRole(OPERATOR) {
        require(levels.length != 0, "empty levels array");
        require(levels[0].requiredMaturity == 0, "levels[0].requiredMaturity != 0");
        if (levels.length > 1) {
            uint highestMaturity;
            for (uint i = 1; i < levels.length; i = _uncheckedInc(i)) {
                require(levels[i].requiredMaturity > highestMaturity, "unsorted levels array");
                highestMaturity = levels[i].requiredMaturity;
            }
        }

        totalAllocPoint += allocPoint;
        lpToken.push(_lpToken);
        rewarder.push(_rewarder);
        nftDescriptor.push(_nftDescriptor);

        poolInfo.push(
            PoolInfo({
                allocPoint: allocPoint,
                lastRewardTime: block.timestamp,
                accOathPerShare: 0,
                levels: levels,
                name: name
            })
        );

        emit LogPoolAddition((lpToken.length - 1), allocPoint, _lpToken, _rewarder, levels, _nftDescriptor);
    }

    /*
     + @notice Modify the given pool's properties.
     +         Can only be called by the owner.
     +
     + @param pid The index of the pool. See `poolInfo`.
     + @param allocPoint New AP of the pool.
     + @param _rewarder Address of the rewarder delegate.
     + @param name Name of pool to be displayed in NFT image
     + @param overwriteRewarder True if _rewarder should be set. Otherwise `_rewarder` is ignored.
     + @param _nftDescriptor The contract address for NFTDescriptor, which will return the token URI
    */
    function modifyPool(
        uint pid,
        uint allocPoint,
        IRewarder _rewarder,
        string calldata name,
        INFTDescriptor _nftDescriptor,
        bool overwriteRewarder
    ) external onlyRole(OPERATOR) {
        require(pid < poolInfo.length, "set: pool does not exist");

        PoolInfo storage pool = poolInfo[pid];
        totalAllocPoint -= pool.allocPoint;
        totalAllocPoint += allocPoint;
        pool.allocPoint = allocPoint;

        if (overwriteRewarder) {
            rewarder[pid] = _rewarder;
        }

        pool.name = name;
        nftDescriptor[pid] = _nftDescriptor;

        emit LogPoolModified(pid, allocPoint, overwriteRewarder ? _rewarder : rewarder[pid], _nftDescriptor);
    }

    /*
     + @notice View function to see pending OATH on frontend.
     + @param relicId ID of the position.
     + @return pending OATH reward for a given position owner.
    */
    function pendingOath(uint relicId) external view override returns (uint pending) {
        _ensureValidPosition(relicId);

        PositionInfo storage position = positionForId[relicId];
        PoolInfo storage pool = poolInfo[position.poolId];
        uint accOathPerShare = pool.accOathPerShare;
        uint lpSupply = _poolBalance(position.poolId);

        uint secondsSinceReward = block.timestamp - pool.lastRewardTime;
        if (secondsSinceReward != 0 && lpSupply != 0) {
            uint oathReward = secondsSinceReward * _baseEmissionsPerSecond() * pool.allocPoint / totalAllocPoint;
            accOathPerShare += oathReward * ACC_OATH_PRECISION / lpSupply;
        }

        uint leveledAmount = position.amount * pool.levels[position.level].allocPoint;
        pending = leveledAmount * accOathPerShare / ACC_OATH_PRECISION + position.rewardCredit - position.rewardDebt;
    }

    /*
     + @notice Update reward variables for all pools. Be careful of gas spending!
     + @param pids Pool IDs of all to be updated. Make sure to update all active pools.
    */
    function massUpdatePools(uint[] calldata pids) external nonReentrant {
        for (uint i; i < pids.length; i = _uncheckedInc(i)) {
            _updatePool(pids[i]);
        }
    }

    /*
     + @notice Update reward variables of the given pool.
     + @param pid The index of the pool. See `poolInfo`.
     + @return pool Returns the pool that was updated.
    */
    function updatePool(uint pid) external nonReentrant {
        _updatePool(pid);
    }

    /// @dev Internal _updatePool function without nonReentrant modifier
    function _updatePool(uint pid) internal {
        require(pid < poolLength(), "invalid pool ID");
        PoolInfo storage pool = poolInfo[pid];
        uint timestamp = block.timestamp;
        uint secondsSinceReward = timestamp - pool.lastRewardTime;

        if (secondsSinceReward != 0) {
            uint lpSupply = _poolBalance(pid);

            if (lpSupply != 0) {
                uint oathReward = secondsSinceReward * _baseEmissionsPerSecond() * pool.allocPoint /
                    totalAllocPoint;
                pool.accOathPerShare += oathReward * ACC_OATH_PRECISION / lpSupply;
            }

            pool.lastRewardTime = timestamp;

            emit LogUpdatePool(pid, timestamp, lpSupply, pool.accOathPerShare);
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
        uint pid,
        uint amount
    ) external nonReentrant returns (uint id) {
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
    function deposit(uint amount, uint relicId) external nonReentrant {
        _ensureValidPosition(relicId);
        require(ownerOf(relicId) == msg.sender, "you do not own this position");
        _deposit(amount, relicId);
    }

    /// @dev Internal deposit function that assumes relicId is valid.
    function _deposit(uint amount, uint relicId) internal {
        require(amount != 0, "depositing 0 amount");

        (uint poolId, ) = _updatePosition(amount, relicId, Kind.DEPOSIT, false);

        lpToken[poolId].safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(poolId, amount, ownerOf(relicId), relicId);
    }

    /*
     + @notice Withdraw LP tokens.
     + @param amount token amount to withdraw.
     + @param relicId NFT ID of the receiver of the tokens and OATH rewards.
    */
    function withdraw(uint amount, uint relicId) external nonReentrant {
        _ensureValidPosition(relicId);
        address to = ownerOf(relicId);
        require(to == msg.sender, "you do not own this position");
        require(amount != 0, "withdrawing 0 amount");

        (uint poolId, ) = _updatePosition(amount, relicId, Kind.WITHDRAW, false);

        lpToken[poolId].safeTransfer(to, amount);

        emit Withdraw(poolId, amount, to, relicId);
    }

    /*
     + @notice Harvest proceeds for transaction sender to owner of `relicId`.
     + @param relicId NFT ID of the receiver of OATH rewards.
    */
    function harvest(uint relicId) external nonReentrant {
        _ensureValidPosition(relicId);
        address to = ownerOf(relicId);
        require(to == msg.sender, "you do not own this position");

        (uint poolId, uint _pendingOath) = _updatePosition(0, relicId, Kind.OTHER, true);

        emit Harvest(poolId, _pendingOath, relicId);
    }

    /*
     + @notice Withdraw LP tokens and harvest proceeds for transaction sender to owner of `relicId`.
     + @param amount token amount to withdraw.
     + @param relicId NFT ID of the receiver of the tokens and OATH rewards.
    */
    function withdrawAndHarvest(uint amount, uint relicId) external nonReentrant {
        _ensureValidPosition(relicId);
        address to = ownerOf(relicId);
        require(to == msg.sender, "you do not own this position");
        require(amount != 0, "withdrawing 0 amount");

        (uint poolId, uint _pendingOath) = _updatePosition(amount, relicId, Kind.WITHDRAW, true);

        lpToken[poolId].safeTransfer(to, amount);

        emit Withdraw(poolId, amount, to, relicId);
        emit Harvest(poolId, _pendingOath, relicId);
    }

    /*
     + @notice Withdraw without caring about rewards. EMERGENCY ONLY.
     + @param relicId NFT ID of the receiver of the tokens.
    */
    function emergencyWithdraw(uint relicId) external nonReentrant {
        _ensureValidPosition(relicId);
        address to = ownerOf(relicId);
        require(to == msg.sender, "you do not own this position");

        PositionInfo storage position = positionForId[relicId];
        uint amount = position.amount;
        uint poolId = position.poolId;
        PoolInfo storage pool = poolInfo[poolId];

        pool.levels[position.level].balance -= amount;

        burn(relicId);
        delete positionForId[relicId];

        lpToken[position.poolId].safeTransfer(to, amount);

        emit EmergencyWithdraw(poolId, amount, to, relicId);
    }

    /// @notice Update position without performing a deposit/withdraw/harvest
    /// @param relicId The NFT ID of the position being updated
    function updatePosition(uint relicId) external nonReentrant {
        _ensureValidPosition(relicId);
        _updatePosition(0, relicId, Kind.OTHER, false);
    }

    /*
     + @dev Internal function called whenever a position's state needs to be modified
     + @param amount Amount of lpToken to deposit/withdraw
     + @param relicId The NFT ID of the position being updated
     + @param kind Indicates whether tokens are being added to, or removed from, a pool
     + @param _harvest Whether a harvest should be performed
     + @return pending OATH reward for a given position owner.
    */
    function _updatePosition(
        uint amount,
        uint relicId,
        Kind kind,
        bool _harvest
    ) internal returns (uint poolId, uint _pendingOath) {
        PositionInfo storage position = positionForId[relicId];
        _updatePool(position.poolId);

        uint oldAmount = position.amount;
        uint newAmount;
        if (kind == Kind.DEPOSIT) {
            _updateEntry(amount, relicId);
            newAmount = oldAmount + amount;
            position.amount = newAmount;
        } else if (kind == Kind.WITHDRAW) {
            newAmount = oldAmount - amount;
            position.amount = newAmount;
            _updateEntry(amount, relicId);
        } else {
            newAmount = oldAmount;
        }

        uint oldLevel = position.level;
        uint newLevel = _updateLevel(relicId);
        poolId = position.poolId;
        PoolInfo storage pool = poolInfo[poolId];
        if (oldLevel != newLevel) {
            pool.levels[oldLevel].balance -= oldAmount;
            pool.levels[newLevel].balance += newAmount;
        } else if (kind == Kind.DEPOSIT) {
            pool.levels[oldLevel].balance += amount;
        } else if (kind == Kind.WITHDRAW) {
            pool.levels[oldLevel].balance -= amount;
        }

        uint leveledAmount = oldAmount * pool.levels[oldLevel].allocPoint;
        uint accumulatedOath = leveledAmount * pool.accOathPerShare / ACC_OATH_PRECISION;
        _pendingOath = accumulatedOath - position.rewardDebt;

        position.rewardDebt = newAmount * pool.levels[newLevel].allocPoint * pool.accOathPerShare / ACC_OATH_PRECISION;

        if (!_harvest && _pendingOath != 0) {
            position.rewardCredit += _pendingOath;
        } else if (_harvest) {
            uint rewardCredit = position.rewardCredit;
            if (rewardCredit != 0) {
                _pendingOath += rewardCredit;
                position.rewardCredit = 0;
            }
            if (_pendingOath != 0) {
                OATH.safeTransfer(msg.sender, _pendingOath);
                IRewarder _rewarder = rewarder[poolId];
                if (address(_rewarder) != address(0)) {
                    _rewarder.onOathReward(relicId, _pendingOath);
                }
            }
        }

        if (kind == Kind.DEPOSIT) {
          IRewarder _rewarder = rewarder[poolId];
          if (address(_rewarder) != address(0)) {
              _rewarder.onDeposit(relicId, amount);
          }
        } else if (kind == Kind.WITHDRAW) {
          IRewarder _rewarder = rewarder[poolId];
          if (address(_rewarder) != address(0)) {
              _rewarder.onWithdraw(relicId, amount);
          }
          if (newAmount == 0) {
              burn(relicId);
              delete (positionForId[relicId]);
          }
        }
    }

    /// @notice Gets the base emission rate from external, upgradable contract
    function _baseEmissionsPerSecond() internal view returns (uint rate) {
        rate = emissionSetter.getRate();
        require(rate <= 6e18, "maximum emission rate exceeded");
    }

    /*
     + @notice Utility function to find weights without any underflows or zero division problems.
     + @param addedValue New value being added
     + @param oldValue Current amount of x
    */
    function _findWeight(uint addedValue, uint oldValue) internal pure returns (uint weightNew) {
      if (oldValue == 0) {
        weightNew = 1e18;
      } else {
        if (addedValue < oldValue) {
          weightNew = addedValue * 1e18 / (addedValue + oldValue);
        } else if (oldValue < addedValue) {
          uint weightOld = oldValue * 1e18 / (addedValue + oldValue);
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
    function _updateEntry(uint amount, uint relicId) internal {
        PositionInfo storage position = positionForId[relicId];
        uint weight = _findWeight(amount, position.amount);
        uint maturity = block.timestamp - position.entry;
        position.entry += maturity * weight / 1e18;
    }

    /*
     + @notice Updates the position's level based on entry time
     + @param relicId The NFT ID of the position being updated
    */
    function _updateLevel(uint relicId) internal returns (uint newLevel) {
        PositionInfo storage position = positionForId[relicId];
        PoolInfo storage pool = poolInfo[position.poolId];
        uint length = pool.levels.length;
        if (length == 1) {
            return 0;
        }

        uint maturity = block.timestamp - position.entry;
        for (uint i = length - 1; true; i = _uncheckedDec(i)) {
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
    function _poolBalance(uint pid) internal view returns (uint total) {
        PoolInfo storage pool = poolInfo[pid];
        uint length = pool.levels.length;
        for (uint i; i < length; i = _uncheckedInc(i)) {
            total += pool.levels[i].balance * pool.levels[i].allocPoint;
        }
    }

    /// @dev Utility function to bypass overflow checking, saving gas
    function _uncheckedInc(uint i) internal pure returns (uint) {
        unchecked {
            return i + 1;
        }
    }

    /// @dev Utility function to bypass underflow checking, saving gas
    function _uncheckedDec(uint i) internal pure returns (uint) {
        unchecked {
            return i - 1;
        }
    }

    /// @notice Existing position is valid if and only if it has non-zero amount.
    function _ensureValidPosition(uint relicId) internal view {
        PositionInfo storage position = positionForId[relicId];
        require(position.amount != 0, "invalid position ID");
    }
}
