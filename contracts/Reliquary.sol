// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./ReliquaryEvents.sol";
import "./interfaces/IReliquary.sol";
import "./interfaces/IRewarder.sol";
import "./interfaces/INFTDescriptor.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

/**
 * @title Reliquary
 * @author Justin Bebis, Zokunei, Beirao & the Byte Masons team
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
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    /// @dev Indicates whether tokens are being added to, or removed from, a pool.
    enum Kind {
        DEPOSIT,
        WITHDRAW,
        OTHER
    }

    /// @dev Access control roles.
    bytes32 private constant OPERATOR = keccak256("OPERATOR");
    bytes32 private constant EMISSION_RATE = keccak256("EMISSION_RATE");

    /// @dev Level of precision rewards are calculated to.
    uint private constant ACC_REWARD_PRECISION = 1e45;

    /// @dev Address of the reward token contract.
    address public immutable rewardToken;
    /// @dev value of emission rate.
    uint256 public emissionRate;
    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint public totalAllocPoint;
    /// @dev Nonce to use for new relicId.
    uint private idNonce;

    /// @dev Address of each NFTDescriptor contract.
    address[] public nftDescriptor;
    /// @dev Info of each Reliquary pool.
    PoolInfo[] private poolInfo;
    /// @dev Address of the LP token for each Reliquary pool.
    address[] public poolToken;
    /// @dev Address of IRewarder contract for each Reliquary pool.
    address[] public rewarder;

    /// @dev Info of each staked position.
    mapping(uint => PositionInfo) internal positionForId;

    // Errors
    error NonExistentRelic();
    error BurningPrincipal();
    error BurningRewards();
    error RewardTokenAsPoolToken();
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
     * @param _emissionRate The contract address for the EmissionRate, which will return the emission rate.
     */
    constructor(address _rewardToken, uint256 _emissionRate, string memory _name, string memory _symbol)
        ERC721(_name, _symbol)
    {
        if (_emissionRate > 6e18) revert MaxEmissionRateExceeded();
        rewardToken = _rewardToken;
        emissionRate = _emissionRate;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @notice Sets a new EmissionRate for overall rewardToken emissions. Can only be called with the proper role.
    /// @param _emissionRate The contract address for the EmissionRate, which will return the base emission rate.
    function setEmissionRate(uint256 _emissionRate) external override onlyRole(EMISSION_RATE) {
        if (_emissionRate > 6e18) revert MaxEmissionRateExceeded();
        emissionRate = _emissionRate;

        emit ReliquaryEvents.LogSetEmissionRate(_emissionRate);
    }

    /**
     * @notice Add a new pool for the specified LP. Can only be called by an operator.
     * @param _allocPoint The allocation points for the new pool.
     * @param _poolToken Address of the pooled ERC-20 token.
     * @param _rewarder Address of the rewarder delegate.
     * @param _curve Curve that will be applied to the pool.
     * @param _name Name of pool to be displayed in NFT image.
     * @param _nftDescriptor The contract address for NFTDescriptor, which will return the token URI.
     * @param _allowPartialWithdrawals Whether users can withdraw less than their entire position. A value of false
     * will also disable shift and split functionality. This is useful for adding pools with decreasing levelMultipliers.
     */
    function addPool(
        uint _allocPoint,
        address _poolToken,
        address _rewarder,
        ICurves _curve,
        string memory _name,
        address _nftDescriptor,
        bool _allowPartialWithdrawals
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_poolToken == rewardToken) revert RewardTokenAsPoolToken();

        for (uint i; i < poolLength();) {
            _updatePool(i);
            unchecked {
                ++i;
            }
        }

        uint totalAlloc = totalAllocPoint + _allocPoint;
        if (totalAlloc == 0) revert ZeroTotalAllocPoint();
        totalAllocPoint = totalAlloc;
        poolToken.push(_poolToken);
        rewarder.push(_rewarder);
        nftDescriptor.push(_nftDescriptor);

        poolInfo.push(
            PoolInfo({
                allocPoint: _allocPoint,
                lastRewardTime: block.timestamp,
                totalLpSupplied: 0,
                curve: _curve,
                accRewardPerShare: 0,
                name: _name,
                allowPartialWithdrawals: _allowPartialWithdrawals
            })
        );
        
        emit ReliquaryEvents.LogPoolAddition(
            (poolToken.length - 1), _allocPoint, _poolToken, _rewarder, _nftDescriptor, _allowPartialWithdrawals
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
    function massUpdatePools() external override nonReentrant {
        for (uint i; i < poolLength(); ) {
            _updatePool(i);
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
        uint levelId = position.level;

        _updatePool(poolId);

        poolInfo[poolId].totalLpSupplied -= amount * poolInfo[poolId].curve.getMultiplerFromLevel(levelId);

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
    function getPoolInfo(uint pid) public view override returns (PoolInfo memory pool) {
        pool = poolInfo[pid];
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
        positionForId[id].poolId = pid;
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

        uint multiplier = _updatePool(poolId) * poolInfo[poolId].curve.getMultiplerFromLevel(level);
        uint pendingFrom = Math.mulDiv(fromAmount, multiplier, ACC_REWARD_PRECISION) - fromPosition.rewardDebt;
        if (pendingFrom != 0) {
            fromPosition.rewardCredit += pendingFrom;
        }

        fromPosition.rewardDebt = Math.mulDiv(newFromAmount, multiplier, ACC_REWARD_PRECISION);
        newPosition.rewardDebt = Math.mulDiv(amount, multiplier, ACC_REWARD_PRECISION);

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
        vars.fromMultiplier = vars.accRewardPerShare * poolInfo[vars.poolId].curve.getMultiplerFromLevel(vars.fromLevel);
        vars.pendingFrom = Math.mulDiv(vars.fromAmount, vars.fromMultiplier, ACC_REWARD_PRECISION) - fromPosition.rewardDebt;
        if (vars.pendingFrom != 0) {
            fromPosition.rewardCredit += vars.pendingFrom;
        }
        vars.pendingTo = Math.mulDiv(vars.toAmount, vars.accRewardPerShare * poolInfo[vars.poolId].curve.getMultiplerFromLevel(vars.oldToLevel), ACC_REWARD_PRECISION) 
            - toPosition.rewardDebt;
        if (vars.pendingTo != 0) {
            toPosition.rewardCredit += vars.pendingTo;
        }
        fromPosition.rewardDebt = Math.mulDiv(vars.newFromAmount, vars.fromMultiplier, ACC_REWARD_PRECISION);
        toPosition.rewardDebt = Math.mulDiv(vars.newToAmount * vars.accRewardPerShare, poolInfo[vars.poolId].curve.getMultiplerFromLevel(vars.newToLevel), ACC_REWARD_PRECISION);

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

        // We split the calculation into two mulDiv()'s to minimise the risk of overflow.
        uint pendingTo = 
             (Math.mulDiv(fromAmount, accRewardPerShare * poolInfo[poolId].curve.getMultiplerFromLevel(fromLevel), ACC_REWARD_PRECISION) 
            + Math.mulDiv(toAmount, accRewardPerShare * poolInfo[poolId].curve.getMultiplerFromLevel(oldToLevel), ACC_REWARD_PRECISION))
            + fromPosition.rewardCredit - fromPosition.rewardDebt - toPosition.rewardDebt;
        
        if (pendingTo != 0) {
            toPosition.rewardCredit += pendingTo;
        }
        toPosition.rewardDebt = 
            Math.mulDiv(newToAmount, accRewardPerShare * poolInfo[poolId].curve.getMultiplerFromLevel(newToLevel), ACC_REWARD_PRECISION);

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
        uint lpSupply = pool.totalLpSupplied;

        uint lastRewardTime = pool.lastRewardTime;
        uint secondsSinceReward = block.timestamp - lastRewardTime;
        if (secondsSinceReward != 0 && lpSupply != 0) {
            uint reward =
                secondsSinceReward * emissionRate * pool.allocPoint / totalAllocPoint;
            accRewardPerShare += Math.mulDiv(reward, ACC_REWARD_PRECISION, lpSupply);
        }

        uint leveledAmount = position.amount * poolInfo[poolId].curve.getMultiplerFromLevel(position.level);
        pending = Math.mulDiv(leveledAmount, accRewardPerShare, ACC_REWARD_PRECISION) + position.rewardCredit - position.rewardDebt;
    }

    /**
     * @notice View function to see level of position if it were to be updated.
     * @dev Uses dichotomous search to scale with large number of levels.
     * @param relicId ID of the position.
     * @return level Level for given position upon update.
     */
    function levelOnUpdate(uint relicId) public view override returns (uint level) {
        PositionInfo storage positionPtr = positionForId[relicId];
        PoolInfo storage poolPtr = poolInfo[positionPtr.poolId];

        if (poolPtr.curve.getNbLevel() == 1) {
            return 0;
        }
        return poolPtr.curve.getLevelFromMaturity(block.timestamp - positionPtr.entry);
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
            uint lpSupply = poolInfo[pid].totalLpSupplied;

            if (lpSupply != 0) {
                uint reward =
                    secondsSinceReward * emissionRate * pool.allocPoint / totalAllocPoint;
                accRewardPerShare += Math.mulDiv(reward, ACC_REWARD_PRECISION, lpSupply);
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
            poolInfo[poolId].totalLpSupplied -= vars.oldAmount * poolInfo[poolId].curve.getMultiplerFromLevel(vars.oldLevel);
            poolInfo[poolId].totalLpSupplied += vars.newAmount * poolInfo[poolId].curve.getMultiplerFromLevel(vars.newLevel);
        } 
        else if (kind == Kind.DEPOSIT) {
            poolInfo[poolId].totalLpSupplied += amount * poolInfo[poolId].curve.getMultiplerFromLevel(vars.oldLevel);
        } 
        else if (kind == Kind.WITHDRAW) {
            poolInfo[poolId].totalLpSupplied -= amount * poolInfo[poolId].curve.getMultiplerFromLevel(vars.oldLevel);
        }

        uint _pendingReward = Math.mulDiv(vars.oldAmount, poolInfo[poolId].curve.getMultiplerFromLevel(vars.oldLevel) * vars.accRewardPerShare, ACC_REWARD_PRECISION) 
            - position.rewardDebt;
        position.rewardDebt =
            Math.mulDiv(vars.newAmount, poolInfo[poolId].curve.getMultiplerFromLevel(vars.newLevel) * vars.accRewardPerShare, ACC_REWARD_PRECISION);

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
        if (oldLevel != newLevel) {
            positionForId[relicId].level = newLevel;
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

        PoolInfo storage pool = poolInfo[poolId];

        if (fromLevel != newToLevel) {
            pool.totalLpSupplied -= amount * pool.curve.getMultiplerFromLevel(fromLevel);
        }
        if (oldToLevel != newToLevel) {
            pool.totalLpSupplied -= toAmount * pool.curve.getMultiplerFromLevel(oldToLevel);
        }

        if (fromLevel != newToLevel && oldToLevel != newToLevel) {
            pool.totalLpSupplied += newToAmount * pool.curve.getMultiplerFromLevel(newToLevel);
        }
        else if (fromLevel != newToLevel) {
            pool.totalLpSupplied += amount * pool.curve.getMultiplerFromLevel(newToLevel);
        }
        else if (oldToLevel != newToLevel) {
            pool.totalLpSupplied += toAmount * pool.curve.getMultiplerFromLevel(newToLevel);
        }
    }

    /// @dev Increments the ID nonce and mints a new Relic to `to`.
    function _mint(address to) private returns (uint id) {
        id = ++idNonce;
        _safeMint(to, id);
    }
}
