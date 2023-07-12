// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./ReliquaryEvents.sol";
import "./interfaces/IReliquary.sol";
import "./interfaces/IEmissionCurve.sol";
import "./interfaces/IRewarder.sol";
import "./interfaces/INFTDescriptor.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "openzeppelin-contracts/contracts/utils/Multicall.sol";
import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

/**
 * @title Reliquary
 * @author Justin Bebis, Zokunei & the Byte Masons team
 *
 * @notice This system is designed to manage incentives for deposited assets such that
 * behaviors can be programmed on a per-pool basis using maturity levels. Stake in a
 * pool, also referred to as "position," is represented by means of an NFT called a
 * "Relic." Each position has a "maturity" which captures the age of the position.
 *
 * @notice Deposits are tracked by Relic ID instead of by user. This allows for
 * increased composability without affecting accounting logic too much, and users can
 * trade their Relics without withdrawing liquidity or affecting the position's maturity.
 */
contract Reliquary is
    IReliquary,
    ERC721Burnable,
    ERC721Enumerable,
    AccessControlEnumerable,
    Multicall,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    /// @dev Access control roles.
    bytes32 private constant OPERATOR = keccak256("OPERATOR");
    bytes32 private constant EMISSION_CURVE = keccak256("EMISSION_CURVE");

    /// @dev Indicates whether tokens are being added to, or removed from, a pool.
    enum Kind {
        DEPOSIT,
        WITHDRAW,
        OTHER
    }

    /// @dev Level of precision rewards are calculated to.
    uint private constant ACC_REWARD_PRECISION = 1e12;

    /// @dev Nonce to use for new relicId.
    uint private idNonce;

    /// @notice Address of the reward token contract.
    address public immutable rewardToken;
    /// @notice Address of each NFTDescriptor contract.
    address[] public nftDescriptor;
    /// @notice Address of EmissionCurve contract.
    address public emissionCurve;
    /// @notice Info of each Reliquary pool.
    PoolInfo[] private poolInfo;
    /// @notice Level system for each Reliquary pool.
    LevelInfo[] private levels;
    /// @notice Address of the LP token for each Reliquary pool.
    address[] public poolToken;
    /// @notice Address of IRewarder contract for each Reliquary pool.
    address[] public rewarder;

    /// @notice Info of each staked position.
    mapping(uint => PositionInfo) internal positionForId;

    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint public totalAllocPoint;

    error NonExistentRelic();
    error BurningPrincipal();
    error BurningRewards();
    error RewardTokenAsPoolToken();
    error EmptyArray();
    error ArrayLengthMismatch();
    error NonZeroFirstMaturity();
    error UnsortedMaturityLevels();
    error ZeroTotalAllocPoint();
    error NonExistentPool();
    error ZeroAmount();
    error NotOwner();
    error DuplicateRelicIds();
    error RelicsNotOfSamePool();
    error MergingEmptyRelics();
    error MaxEmissionRateExceeded();
    error NotApprovedOrOwner();
    error PartialWithdrawalsDisabled();

    /**
     * @dev Constructs and initializes the contract.
     * @param _rewardToken The reward token contract address.
     * @param _emissionCurve The contract address for the EmissionCurve, which will return the emission rate.
     */
    constructor(address _rewardToken, address _emissionCurve, string memory name, string memory symbol)
        ERC721(name, symbol)
    {
        rewardToken = _rewardToken;
        emissionCurve = _emissionCurve;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @notice Sets a new EmissionCurve for overall rewardToken emissions. Can only be called with the proper role.
    /// @param _emissionCurve The contract address for the EmissionCurve, which will return the base emission rate.
    function setEmissionCurve(address _emissionCurve) external override onlyRole(EMISSION_CURVE) {
        emissionCurve = _emissionCurve;
        emit ReliquaryEvents.LogSetEmissionCurve(_emissionCurve);
    }

    /**
     * @notice Add a new pool for the specified LP. Can only be called by an operator.
     * @param allocPoint The allocation points for the new pool.
     * @param _poolToken Address of the pooled ERC-20 token.
     * @param _rewarder Address of the rewarder delegate.
     * @param requiredMaturities Array of maturity (in seconds) required to achieve each level for this pool.
     * @param levelMultipliers The multipliers applied to the amount of `_poolToken` for each level within this pool.
     * @param name Name of pool to be displayed in NFT image.
     * @param _nftDescriptor The contract address for NFTDescriptor, which will return the token URI.
     * @param allowPartialWithdrawals Whether users can withdraw less than their entire position. A value of false
     * will also disable shift and split functionality. This is useful for adding pools with decreasing levelMultipliers.
     */
    function addPool(
        uint allocPoint,
        address _poolToken,
        address _rewarder,
        uint[] calldata requiredMaturities,
        uint[] calldata levelMultipliers,
        string memory name,
        address _nftDescriptor,
        bool allowPartialWithdrawals
    ) external override onlyRole(OPERATOR) {
        if (_poolToken == rewardToken) revert RewardTokenAsPoolToken();
        if (requiredMaturities.length == 0) revert EmptyArray();
        if (requiredMaturities.length != levelMultipliers.length) revert ArrayLengthMismatch();
        if (requiredMaturities[0] != 0) revert NonZeroFirstMaturity();
        if (requiredMaturities.length > 1) {
            uint highestMaturity;
            for (uint i = 1; i < requiredMaturities.length;) {
                if (requiredMaturities[i] <= highestMaturity) revert UnsortedMaturityLevels();
                highestMaturity = requiredMaturities[i];
                unchecked {
                    ++i;
                }
            }
        }

        for (uint i; i < poolLength();) {
            _updatePool(i);
            unchecked {
                ++i;
            }
        }

        uint totalAlloc = totalAllocPoint + allocPoint;
        if (totalAlloc == 0) revert ZeroTotalAllocPoint();
        totalAllocPoint = totalAlloc;
        poolToken.push(_poolToken);
        rewarder.push(_rewarder);
        nftDescriptor.push(_nftDescriptor);

        poolInfo.push(
            PoolInfo({
                allocPoint: allocPoint,
                lastRewardTime: block.timestamp,
                accRewardPerShare: 0,
                name: name,
                allowPartialWithdrawals: allowPartialWithdrawals
            })
        );
        levels.push(
            LevelInfo({
                requiredMaturities: requiredMaturities,
                multipliers: levelMultipliers,
                balance: new uint[](levelMultipliers.length)
            })
        );

        emit ReliquaryEvents.LogPoolAddition(
            (poolToken.length - 1), allocPoint, _poolToken, _rewarder, _nftDescriptor, allowPartialWithdrawals
        );
    }

    /**
     * @notice Modify the given pool's properties. Can only be called by an operator.
     * @param pid The index of the pool. See poolInfo.
     * @param allocPoint New AP of the pool.
     * @param _rewarder Address of the rewarder delegate.
     * @param name Name of pool to be displayed in NFT image.
     * @param _nftDescriptor The contract address for NFTDescriptor, which will return the token URI.
     * @param overwriteRewarder True if _rewarder should be set. Otherwise _rewarder is ignored.
     */
    function modifyPool(
        uint pid,
        uint allocPoint,
        address _rewarder,
        string calldata name,
        address _nftDescriptor,
        bool overwriteRewarder
    ) external override onlyRole(OPERATOR) {
        if (pid >= poolInfo.length) revert NonExistentPool();

        uint length = poolLength();
        for (uint i; i < length;) {
            _updatePool(i);
            unchecked {
                ++i;
            }
        }

        PoolInfo storage pool = poolInfo[pid];
        uint totalAlloc = totalAllocPoint + allocPoint - pool.allocPoint;
        if (totalAlloc == 0) revert ZeroTotalAllocPoint();
        totalAllocPoint = totalAlloc;
        pool.allocPoint = allocPoint;

        if (overwriteRewarder) {
            rewarder[pid] = _rewarder;
        }

        pool.name = name;
        nftDescriptor[pid] = _nftDescriptor;

        emit ReliquaryEvents.LogPoolModified(
            pid, allocPoint, overwriteRewarder ? _rewarder : rewarder[pid], _nftDescriptor
        );
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    /// @param pids Pool IDs of all to be updated. Make sure to update all active pools.
    function massUpdatePools(uint[] calldata pids) external override nonReentrant {
        for (uint i; i < pids.length;) {
            _updatePool(pids[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See poolInfo.
    function updatePool(uint pid) external override nonReentrant {
        _updatePool(pid);
    }

    /**
     * @notice Deposit pool tokens to Reliquary for reward token allocation.
     * @param amount Token amount to deposit.
     * @param relicId NFT ID of the position being deposited to.
     */
    function deposit(uint amount, uint relicId) external override nonReentrant {
        _requireApprovedOrOwner(relicId);
        _deposit(amount, relicId);
    }

    /**
     * @notice Withdraw pool tokens.
     * @param amount token amount to withdraw.
     * @param relicId NFT ID of the position being withdrawn.
     */
    function withdraw(uint amount, uint relicId) external override nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _requireApprovedOrOwner(relicId);

        (uint poolId,) = _updatePosition(amount, relicId, Kind.WITHDRAW, address(0));

        IERC20(poolToken[poolId]).safeTransfer(msg.sender, amount);

        emit ReliquaryEvents.Withdraw(poolId, amount, msg.sender, relicId);
    }

    /**
     * @notice Harvest proceeds for transaction sender to owner of Relic `relicId`.
     * @param relicId NFT ID of the position being harvested.
     * @param harvestTo Address to send rewards to (zero address if harvest should not be performed).
     */
    function harvest(uint relicId, address harvestTo) external override nonReentrant {
        _requireApprovedOrOwner(relicId);

        (uint poolId, uint receivedReward) = _updatePosition(0, relicId, Kind.OTHER, harvestTo);

        emit ReliquaryEvents.Harvest(poolId, receivedReward, harvestTo, relicId);
    }

    /**
     * @notice Withdraw pool tokens and harvest proceeds for transaction sender to owner of Relic `relicId`.
     * @param amount token amount to withdraw.
     * @param relicId NFT ID of the position being withdrawn and harvested.
     * @param harvestTo Address to send rewards to (zero address if harvest should not be performed).
     */
    function withdrawAndHarvest(uint amount, uint relicId, address harvestTo) external override nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _requireApprovedOrOwner(relicId);

        (uint poolId, uint receivedReward) = _updatePosition(amount, relicId, Kind.WITHDRAW, harvestTo);

        IERC20(poolToken[poolId]).safeTransfer(msg.sender, amount);

        emit ReliquaryEvents.Withdraw(poolId, amount, msg.sender, relicId);
        emit ReliquaryEvents.Harvest(poolId, receivedReward, harvestTo, relicId);
    }

    /**
     * @notice Withdraw without caring about rewards. EMERGENCY ONLY.
     * @param relicId NFT ID of the position to emergency withdraw from and burn.
     */
    function emergencyWithdraw(uint relicId) external override nonReentrant {
        address to = ownerOf(relicId);
        if (to != msg.sender) revert NotOwner();

        PositionInfo storage position = positionForId[relicId];
        uint amount = position.amount;
        uint poolId = position.poolId;

        levels[poolId].balance[position.level] -= amount;

        _burn(relicId);
        delete positionForId[relicId];

        IERC20(poolToken[poolId]).safeTransfer(to, amount);

        emit ReliquaryEvents.EmergencyWithdraw(poolId, amount, to, relicId);
    }

    /// @notice Update position without performing a deposit/withdraw/harvest.
    /// @param relicId The NFT ID of the position being updated.
    function updatePosition(uint relicId) external override nonReentrant {
        if (!_exists(relicId)) revert NonExistentRelic();
        _updatePosition(0, relicId, Kind.OTHER, address(0));
    }

    /// @notice Returns a PositionInfo object for the given relicId.
    function getPositionForId(uint relicId) external view override returns (PositionInfo memory position) {
        position = positionForId[relicId];
    }

    /// @notice Returns a PoolInfo object for pool ID `pid`.
    function getPoolInfo(uint pid) external view override returns (PoolInfo memory pool) {
        pool = poolInfo[pid];
    }

    /// @notice Returns a LevelInfo object for pool ID `pid`.
    function getLevelInfo(uint pid) external view override returns (LevelInfo memory levelInfo) {
        levelInfo = levels[pid];
    }

    /**
     * @notice View function to retrieve the relicIds, poolIds, and pendingReward for each Relic owned by an address.
     * @param owner Address of the owner to retrieve info for.
     * @return pendingRewards Array of PendingReward objects.
     */
    function pendingRewardsOfOwner(address owner)
        external
        view
        override
        returns (PendingReward[] memory pendingRewards)
    {
        uint balance = balanceOf(owner);
        pendingRewards = new PendingReward[](balance);
        for (uint i; i < balance;) {
            uint relicId = tokenOfOwnerByIndex(owner, i);
            pendingRewards[i] = PendingReward({
                relicId: relicId,
                poolId: positionForId[relicId].poolId,
                pendingReward: pendingReward(relicId)
            });
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice View function to retrieve owned positions for an address.
     * @param owner Address of the owner to retrieve info for.
     * @return relicIds Each relicId owned by the given address.
     * @return positionInfos The PositionInfo object for each relicId.
     */
    function relicPositionsOfOwner(address owner)
        external
        view
        override
        returns (uint[] memory relicIds, PositionInfo[] memory positionInfos)
    {
        uint balance = balanceOf(owner);
        relicIds = new uint[](balance);
        positionInfos = new PositionInfo[](balance);
        for (uint i; i < balance;) {
            relicIds[i] = tokenOfOwnerByIndex(owner, i);
            positionInfos[i] = positionForId[relicIds[i]];
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns whether `spender` is allowed to manage Relic `relicId`.
    function isApprovedOrOwner(address spender, uint relicId) external view override returns (bool) {
        return _isApprovedOrOwner(spender, relicId);
    }

    /**
     * @notice Create a new Relic NFT and deposit into this position.
     * @param to Address to mint the Relic to.
     * @param pid The index of the pool. See poolInfo.
     * @param amount Token amount to deposit.
     */
    function createRelicAndDeposit(address to, uint pid, uint amount)
        public
        virtual
        override
        nonReentrant
        returns (uint id)
    {
        if (pid >= poolInfo.length) revert NonExistentPool();
        id = _mint(to);
        PositionInfo storage position = positionForId[id];
        position.poolId = pid;
        _deposit(amount, id);
        emit ReliquaryEvents.CreateRelic(pid, to, id);
    }

    /**
     * @notice Split an owned Relic into a new one, while maintaining maturity.
     * @param fromId The NFT ID of the Relic to split from.
     * @param amount Amount to move from existing Relic into the new one.
     * @param to Address to mint the Relic to.
     * @return newId The NFT ID of the new Relic.
     */
    function split(uint fromId, uint amount, address to) public virtual override nonReentrant returns (uint newId) {
        if (amount == 0) revert ZeroAmount();
        _requireApprovedOrOwner(fromId);

        PositionInfo storage fromPosition = positionForId[fromId];
        uint poolId = fromPosition.poolId;
        if (!poolInfo[poolId].allowPartialWithdrawals) revert PartialWithdrawalsDisabled();

        uint fromAmount = fromPosition.amount;
        uint newFromAmount = fromAmount - amount;
        fromPosition.amount = newFromAmount;

        newId = _mint(to);
        PositionInfo storage newPosition = positionForId[newId];
        newPosition.amount = amount;
        newPosition.entry = fromPosition.entry;
        uint level = fromPosition.level;
        newPosition.level = level;
        newPosition.poolId = poolId;

        uint multiplier = _updatePool(poolId) * levels[poolId].multipliers[level];
        uint pendingFrom = fromAmount * multiplier / ACC_REWARD_PRECISION - fromPosition.rewardDebt;
        if (pendingFrom != 0) {
            fromPosition.rewardCredit += pendingFrom;
        }
        fromPosition.rewardDebt = newFromAmount * multiplier / ACC_REWARD_PRECISION;
        newPosition.rewardDebt = amount * multiplier / ACC_REWARD_PRECISION;

        emit ReliquaryEvents.CreateRelic(poolId, to, newId);
        emit ReliquaryEvents.Split(fromId, newId, amount);
    }

    struct LocalVariables_shift {
        uint fromAmount;
        uint poolId;
        uint toAmount;
        uint newFromAmount;
        uint newToAmount;
        uint fromLevel;
        uint oldToLevel;
        uint newToLevel;
        uint accRewardPerShare;
        uint fromMultiplier;
        uint pendingFrom;
        uint pendingTo;
    }

    /**
     * @notice Transfer amount from one Relic into another, updating maturity in the receiving Relic.
     * @param fromId The NFT ID of the Relic to transfer from.
     * @param toId The NFT ID of the Relic being transferred to.
     * @param amount The amount being transferred.
     */
    function shift(uint fromId, uint toId, uint amount) public virtual override nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (fromId == toId) revert DuplicateRelicIds();
        _requireApprovedOrOwner(fromId);
        _requireApprovedOrOwner(toId);

        LocalVariables_shift memory vars;
        PositionInfo storage fromPosition = positionForId[fromId];
        vars.poolId = fromPosition.poolId;
        if (!poolInfo[vars.poolId].allowPartialWithdrawals) revert PartialWithdrawalsDisabled();

        PositionInfo storage toPosition = positionForId[toId];
        if (vars.poolId != toPosition.poolId) revert RelicsNotOfSamePool();

        vars.fromAmount = fromPosition.amount;
        vars.toAmount = toPosition.amount;
        toPosition.entry = (vars.fromAmount * fromPosition.entry + vars.toAmount * toPosition.entry)
            / (vars.fromAmount + vars.toAmount);

        vars.newFromAmount = vars.fromAmount - amount;
        fromPosition.amount = vars.newFromAmount;

        vars.newToAmount = vars.toAmount + amount;
        toPosition.amount = vars.newToAmount;

        (vars.fromLevel, vars.oldToLevel, vars.newToLevel) =
            _shiftLevelBalances(fromId, toId, vars.poolId, amount, vars.toAmount, vars.newToAmount);

        vars.accRewardPerShare = _updatePool(vars.poolId);
        vars.fromMultiplier = vars.accRewardPerShare * levels[vars.poolId].multipliers[vars.fromLevel];
        vars.pendingFrom = vars.fromAmount * vars.fromMultiplier / ACC_REWARD_PRECISION - fromPosition.rewardDebt;
        if (vars.pendingFrom != 0) {
            fromPosition.rewardCredit += vars.pendingFrom;
        }
        vars.pendingTo = vars.toAmount * levels[vars.poolId].multipliers[vars.oldToLevel] * vars.accRewardPerShare
            / ACC_REWARD_PRECISION - toPosition.rewardDebt;
        if (vars.pendingTo != 0) {
            toPosition.rewardCredit += vars.pendingTo;
        }
        fromPosition.rewardDebt = vars.newFromAmount * vars.fromMultiplier / ACC_REWARD_PRECISION;
        toPosition.rewardDebt = vars.newToAmount * vars.accRewardPerShare
            * levels[vars.poolId].multipliers[vars.newToLevel] / ACC_REWARD_PRECISION;

        emit ReliquaryEvents.Shift(fromId, toId, amount);
    }

    /**
     * @notice Transfer entire position (including rewards) from one Relic into another, burning it
     * and updating maturity in the receiving Relic.
     * @param fromId The NFT ID of the Relic to transfer from.
     * @param toId The NFT ID of the Relic being transferred to.
     */
    function merge(uint fromId, uint toId) public virtual override nonReentrant {
        if (fromId == toId) revert DuplicateRelicIds();
        _requireApprovedOrOwner(fromId);
        _requireApprovedOrOwner(toId);

        PositionInfo storage fromPosition = positionForId[fromId];
        uint fromAmount = fromPosition.amount;

        uint poolId = fromPosition.poolId;
        PositionInfo storage toPosition = positionForId[toId];
        if (poolId != toPosition.poolId) revert RelicsNotOfSamePool();

        uint toAmount = toPosition.amount;
        uint newToAmount = toAmount + fromAmount;
        if (newToAmount == 0) revert MergingEmptyRelics();
        toPosition.entry = (fromAmount * fromPosition.entry + toAmount * toPosition.entry) / newToAmount;

        toPosition.amount = newToAmount;

        (uint fromLevel, uint oldToLevel, uint newToLevel) =
            _shiftLevelBalances(fromId, toId, poolId, fromAmount, toAmount, newToAmount);

        uint accRewardPerShare = _updatePool(poolId);
        uint pendingTo = accRewardPerShare
            * (fromAmount * levels[poolId].multipliers[fromLevel] + toAmount * levels[poolId].multipliers[oldToLevel])
            / ACC_REWARD_PRECISION + fromPosition.rewardCredit - fromPosition.rewardDebt - toPosition.rewardDebt;
        if (pendingTo != 0) {
            toPosition.rewardCredit += pendingTo;
        }
        toPosition.rewardDebt =
            newToAmount * accRewardPerShare * levels[poolId].multipliers[newToLevel] / ACC_REWARD_PRECISION;

        _burn(fromId);
        delete positionForId[fromId];

        emit ReliquaryEvents.Merge(fromId, toId, fromAmount);
    }

    /// @notice Burns the Relic with ID `tokenId`. Cannot be called if there is any principal or rewards in the Relic.
    function burn(uint tokenId) public virtual override(IReliquary, ERC721Burnable) {
        if (positionForId[tokenId].amount != 0) revert BurningPrincipal();
        if (pendingReward(tokenId) != 0) revert BurningRewards();
        super.burn(tokenId);
    }

    /**
     * @notice View function to see pending reward tokens on frontend.
     * @param relicId ID of the position.
     * @return pending reward amount for a given position owner.
     */
    function pendingReward(uint relicId) public view override returns (uint pending) {
        PositionInfo storage position = positionForId[relicId];
        uint poolId = position.poolId;
        PoolInfo storage pool = poolInfo[poolId];
        uint accRewardPerShare = pool.accRewardPerShare;
        uint lpSupply = _poolBalance(position.poolId);

        uint lastRewardTime = pool.lastRewardTime;
        uint secondsSinceReward = block.timestamp - lastRewardTime;
        if (secondsSinceReward != 0 && lpSupply != 0) {
            uint reward =
                secondsSinceReward * _baseEmissionsPerSecond(lastRewardTime) * pool.allocPoint / totalAllocPoint;
            accRewardPerShare += reward * ACC_REWARD_PRECISION / lpSupply;
        }

        uint leveledAmount = position.amount * levels[poolId].multipliers[position.level];
        pending = leveledAmount * accRewardPerShare / ACC_REWARD_PRECISION + position.rewardCredit - position.rewardDebt;
    }

    /**
     * @notice View function to see level of position if it were to be updated.
     * @param relicId ID of the position.
     * @return level Level for given position upon update.
     */
    function levelOnUpdate(uint relicId) public view override returns (uint level) {
        PositionInfo storage position = positionForId[relicId];
        LevelInfo storage levelInfo = levels[position.poolId];
        uint length = levelInfo.requiredMaturities.length;
        if (length == 1) {
            return 0;
        }

        uint maturity = block.timestamp - position.entry;
        for (level = length - 1; true;) {
            if (maturity >= levelInfo.requiredMaturities[level]) {
                break;
            }
            unchecked {
                --level;
            }
        }
    }

    /// @notice Returns the number of Reliquary pools.
    function poolLength() public view override returns (uint pools) {
        pools = poolInfo.length;
    }

    /**
     * @notice Returns the ERC721 tokenURI given by the pool's NFTDescriptor.
     * @dev Can be gas expensive if used in a transaction and the NFTDescriptor is complex.
     * @param tokenId The NFT ID of the Relic to get the tokenURI for.
     */
    function tokenURI(uint tokenId) public view override(ERC721) returns (string memory) {
        if (!_exists(tokenId)) revert NonExistentRelic();
        return INFTDescriptor(nftDescriptor[positionForId[tokenId].poolId]).constructTokenURI(tokenId);
    }

    /// @dev Implement ERC165 to return which interfaces this contract conforms to
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IERC165, AccessControlEnumerable, ERC721, ERC721Enumerable)
        returns (bool)
    {
        return interfaceId == type(IReliquary).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @dev Internal _updatePool function without nonReentrant modifier.
    function _updatePool(uint pid) internal returns (uint accRewardPerShare) {
        if (pid >= poolLength()) revert NonExistentPool();
        PoolInfo storage pool = poolInfo[pid];
        uint timestamp = block.timestamp;
        uint lastRewardTime = pool.lastRewardTime;
        uint secondsSinceReward = timestamp - lastRewardTime;

        accRewardPerShare = pool.accRewardPerShare;
        if (secondsSinceReward != 0) {
            uint lpSupply = _poolBalance(pid);

            if (lpSupply != 0) {
                uint reward =
                    secondsSinceReward * _baseEmissionsPerSecond(lastRewardTime) * pool.allocPoint / totalAllocPoint;
                accRewardPerShare += reward * ACC_REWARD_PRECISION / lpSupply;
                pool.accRewardPerShare = accRewardPerShare;
            }

            pool.lastRewardTime = timestamp;

            emit ReliquaryEvents.LogUpdatePool(pid, timestamp, lpSupply, accRewardPerShare);
        }
    }

    /// @dev Internal deposit function that assumes relicId is valid.
    function _deposit(uint amount, uint relicId) internal {
        if (amount == 0) revert ZeroAmount();

        (uint poolId,) = _updatePosition(amount, relicId, Kind.DEPOSIT, address(0));

        IERC20(poolToken[poolId]).safeTransferFrom(msg.sender, address(this), amount);

        emit ReliquaryEvents.Deposit(poolId, amount, ownerOf(relicId), relicId);
    }

    struct LocalVariables_updatePosition {
        uint accRewardPerShare;
        uint oldAmount;
        uint newAmount;
        uint oldLevel;
        uint newLevel;
        bool harvest;
    }

    /**
     * @dev Internal function called whenever a position's state needs to be modified.
     * @param amount Amount of poolToken to deposit/withdraw.
     * @param relicId The NFT ID of the position being updated.
     * @param kind Indicates whether tokens are being added to, or removed from, a pool.
     * @param harvestTo Address to send rewards to (zero address if harvest should not be performed).
     * @return poolId Pool ID of the given position.
     * @return received Amount of reward token dispensed to `harvestTo` on harvest.
     */
    function _updatePosition(uint amount, uint relicId, Kind kind, address harvestTo)
        internal
        returns (uint poolId, uint received)
    {
        LocalVariables_updatePosition memory vars;
        PositionInfo storage position = positionForId[relicId];
        poolId = position.poolId;
        vars.accRewardPerShare = _updatePool(poolId);

        vars.oldAmount = position.amount;
        if (kind == Kind.DEPOSIT) {
            _updateEntry(amount, relicId);
            vars.newAmount = vars.oldAmount + amount;
            position.amount = vars.newAmount;
        } else if (kind == Kind.WITHDRAW) {
            if (amount != vars.oldAmount && !poolInfo[poolId].allowPartialWithdrawals) {
                revert PartialWithdrawalsDisabled();
            }
            vars.newAmount = vars.oldAmount - amount;
            position.amount = vars.newAmount;
        } else {
            vars.newAmount = vars.oldAmount;
        }

        vars.oldLevel = position.level;
        vars.newLevel = _updateLevel(relicId, vars.oldLevel);
        if (vars.oldLevel != vars.newLevel) {
            levels[poolId].balance[vars.oldLevel] -= vars.oldAmount;
            levels[poolId].balance[vars.newLevel] += vars.newAmount;
        } else if (kind == Kind.DEPOSIT) {
            levels[poolId].balance[vars.oldLevel] += amount;
        } else if (kind == Kind.WITHDRAW) {
            levels[poolId].balance[vars.oldLevel] -= amount;
        }

        uint _pendingReward = vars.oldAmount * levels[poolId].multipliers[vars.oldLevel] * vars.accRewardPerShare
            / ACC_REWARD_PRECISION - position.rewardDebt;
        position.rewardDebt =
            vars.newAmount * levels[poolId].multipliers[vars.newLevel] * vars.accRewardPerShare / ACC_REWARD_PRECISION;

        vars.harvest = harvestTo != address(0);
        if (!vars.harvest && _pendingReward != 0) {
            position.rewardCredit += _pendingReward;
        } else if (vars.harvest) {
            uint total = _pendingReward + position.rewardCredit;
            received = _receivedReward(total);
            position.rewardCredit = total - received;
            if (received != 0) {
                IERC20(rewardToken).safeTransfer(harvestTo, received);
            }
            address _rewarder = rewarder[poolId];
            if (_rewarder != address(0)) {
                IRewarder(_rewarder).onReward(relicId, received, harvestTo);
            }
        }

        if (kind == Kind.DEPOSIT) {
            address _rewarder = rewarder[poolId];
            if (_rewarder != address(0)) {
                IRewarder(_rewarder).onDeposit(relicId, amount);
            }
        } else if (kind == Kind.WITHDRAW) {
            address _rewarder = rewarder[poolId];
            if (_rewarder != address(0)) {
                IRewarder(_rewarder).onWithdraw(relicId, amount);
            }
        }
    }

    /**
     * @notice Updates the user's entry time based on the weight of their deposit or withdrawal.
     * @param amount The amount of the deposit / withdrawal.
     * @param relicId The NFT ID of the position being updated.
     */
    function _updateEntry(uint amount, uint relicId) internal {
        PositionInfo storage position = positionForId[relicId];
        uint amountBefore = position.amount;
        if (amountBefore == 0) {
            position.entry = block.timestamp;
        } else {
            uint weight = _findWeight(amount, amountBefore);
            uint entryBefore = position.entry;
            uint maturity = block.timestamp - entryBefore;
            position.entry = entryBefore + maturity * weight / 1e12;
        }
    }

    /**
     * @notice Updates the position's level based on entry time.
     * @param relicId The NFT ID of the position being updated.
     * @param oldLevel Level of position before update.
     * @return newLevel Level of position after update.
     */
    function _updateLevel(uint relicId, uint oldLevel) internal returns (uint newLevel) {
        newLevel = levelOnUpdate(relicId);
        PositionInfo storage position = positionForId[relicId];
        if (oldLevel != newLevel) {
            position.level = newLevel;
            emit ReliquaryEvents.LevelChanged(relicId, newLevel);
        }
    }

    /// @dev Ensure the behavior of ERC721Enumerable _beforeTokenTransfer is preserved.
    function _beforeTokenTransfer(address from, address to, uint tokenId, uint batchSize)
        internal
        override(ERC721, ERC721Enumerable)
    {
        ERC721Enumerable._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /**
     * @notice Calculate how much the owner will actually receive on harvest, given available reward tokens.
     * @param _pendingReward Amount of reward token owed.
     * @return received The minimum between amount owed and amount available.
     */
    function _receivedReward(uint _pendingReward) internal view returns (uint received) {
        uint available = IERC20(rewardToken).balanceOf(address(this));
        received = (available > _pendingReward) ? _pendingReward : available;
    }

    /// @notice Gets the base emission rate from external, upgradable contract.
    function _baseEmissionsPerSecond(uint lastRewardTime) internal view returns (uint rate) {
        rate = IEmissionCurve(emissionCurve).getRate(lastRewardTime);
        if (rate > 6e18) revert MaxEmissionRateExceeded();
    }

    /**
     * @notice returns The total deposits of the pool's token, weighted by maturity level allocation.
     * @param pid The index of the pool. See poolInfo.
     * @return total The amount of pool tokens held by the contract.
     */
    function _poolBalance(uint pid) internal view returns (uint total) {
        LevelInfo storage levelInfo = levels[pid];
        uint length = levelInfo.balance.length;
        for (uint i; i < length;) {
            total += levelInfo.balance[i] * levelInfo.multipliers[i];
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Require the sender is either the owner of the Relic or approved to transfer it.
    /// @param relicId The NFT ID of the Relic.
    function _requireApprovedOrOwner(uint relicId) internal view {
        if (!_isApprovedOrOwner(msg.sender, relicId)) revert NotApprovedOrOwner();
    }

    /**
     * @notice Used in `_updateEntry` to find weights without any underflows or zero division problems.
     * @param addedValue New value being added.
     * @param oldValue Current amount of x.
     */
    function _findWeight(uint addedValue, uint oldValue) internal pure returns (uint weightNew) {
        if (oldValue < addedValue) {
            weightNew = 1e12 - oldValue * 1e12 / (addedValue + oldValue);
        } else if (addedValue < oldValue) {
            weightNew = addedValue * 1e12 / (addedValue + oldValue);
        } else {
            weightNew = 5e11;
        }
    }

    /// @dev Handle updating balances for each affected tranche when shifting and merging.
    function _shiftLevelBalances(uint fromId, uint toId, uint poolId, uint amount, uint toAmount, uint newToAmount)
        private
        returns (uint fromLevel, uint oldToLevel, uint newToLevel)
    {
        fromLevel = positionForId[fromId].level;
        oldToLevel = positionForId[toId].level;
        newToLevel = _updateLevel(toId, oldToLevel);
        if (fromLevel != newToLevel) {
            levels[poolId].balance[fromLevel] -= amount;
        }
        if (oldToLevel != newToLevel) {
            levels[poolId].balance[oldToLevel] -= toAmount;
        }
        if (fromLevel != newToLevel && oldToLevel != newToLevel) {
            levels[poolId].balance[newToLevel] += newToAmount;
        } else if (fromLevel != newToLevel) {
            levels[poolId].balance[newToLevel] += amount;
        } else if (oldToLevel != newToLevel) {
            levels[poolId].balance[newToLevel] += toAmount;
        }
    }

    /// @dev Increments the ID nonce and mints a new Relic to `to`.
    function _mint(address to) private returns (uint id) {
        id = ++idNonce;
        _safeMint(to, id);
    }
}
