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
    uint256 private constant ACC_REWARD_PRECISION = 1e45;
    /// @dev SHIBA supply for checks purpose.
    uint256 private constant SHIBA_SUPPLY = 589280962856592 ether;

    /// @dev Address of the reward token contract.
    address public immutable rewardToken;
    /// @dev value of emission rate.
    uint256 public emissionRate;
    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    /// @dev Nonce to use for new relicId.
    uint256 private idNonce;

    /// @dev Info of each Reliquary pool.
    PoolInfo[] private poolInfo;
    /// @dev Info of each staked position.
    mapping(uint256 => PositionInfo) internal positionForId;

    // Errors
    error Reliquary__NON_EXISTENT_RELIC();
    error Reliquary__BURNING_PRINCIPAL();
    error Reliquary__BURNING_REWARDS();
    error Reliquary__REWARD_TOKEN_AS_POOL_TOKEN();
    error Reliquary__ZERO_TOTAL_ALLOC_POINT();
    error Reliquary__NON_EXISTENT_POOL();
    error Reliquary__ZERO_AMOUNT();
    error Reliquary__NOT_OWNER();
    error Reliquary__DUPLICATE_RELIC_IDS();
    error Reliquary__RELICS_NOT_OF_SAME_POOL();
    error Reliquary__MERGING_EMPTY_RELICS();
    error Reliquary__MAX_EMISSION_RATE_EXCEEDED();
    error Reliquary__NOT_APPROVED_OR_OWNER();
    error Reliquary__PARTIAL_WITHDRAWALS_DISABLED();
    error Reliquary__MULTIPLIER_AT_MATURITY_ZERO_SHOULD_BE_GT_ZERO();
    error Reliquary__REWARD_PRECISION_ISSUE();

    /**
     * @dev Constructs and initializes the contract.
     * @param _rewardToken The reward token contract address.
     * @param _emissionRate The contract address for the EmissionRate, which will return the emission rate.
     */
    constructor(
        address _rewardToken,
        uint256 _emissionRate,
        string memory _name,
        string memory _symbol
    ) ERC721(_name, _symbol) {
        if (_emissionRate > 6e18) revert Reliquary__MAX_EMISSION_RATE_EXCEEDED();
        rewardToken = _rewardToken;
        emissionRate = _emissionRate;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Sets a new EmissionRate for overall rewardToken emissions. Can only be called with the proper role.
     * @param _emissionRate The contract address for the EmissionRate, which will return the base emission rate.
     */
    function setEmissionRate(uint256 _emissionRate) external override onlyRole(EMISSION_RATE) {
        if (_emissionRate > 6e18) revert Reliquary__MAX_EMISSION_RATE_EXCEEDED();
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
        uint256 _allocPoint,
        address _poolToken,
        address _rewarder,
        ICurves _curve,
        string memory _name,
        address _nftDescriptor,
        bool _allowPartialWithdrawals
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_poolToken == rewardToken) revert Reliquary__REWARD_TOKEN_AS_POOL_TOKEN();

        for (uint256 i_; i_ < poolLength();) {
            _updatePool(i_);
            unchecked {
                ++i_;
            }
        }
        if (_curve.getFunction(0) == 0) {
            revert Reliquary__MULTIPLIER_AT_MATURITY_ZERO_SHOULD_BE_GT_ZERO();
        }

        // All SHIBA supply in 10 years should not round down at 0 in case of division
        if (ACC_REWARD_PRECISION < SHIBA_SUPPLY * _curve.getFunction(365 days * 10)) {
            revert Reliquary__REWARD_PRECISION_ISSUE();
        }

        //! _curve must be strictly increasing.
        //! We can't check this rule since curve are defined in [0, +infinity]

        uint256 totalAlloc_ = totalAllocPoint + _allocPoint;
        if (totalAlloc_ == 0) revert Reliquary__ZERO_TOTAL_ALLOC_POINT();
        totalAllocPoint = totalAlloc_;

        poolInfo.push(
            PoolInfo({
                allocPoint: _allocPoint,
                lastRewardTime: block.timestamp,
                totalLpSupplied: 0,
                curve: _curve,
                accRewardPerShare: 0,
                name: _name,
                allowPartialWithdrawals: _allowPartialWithdrawals,
                nftDescriptor: _nftDescriptor,
                rewarder: _rewarder,
                poolToken: _poolToken
            })
        );

        emit ReliquaryEvents.LogPoolAddition(
            (poolInfo.length - 1),
            _allocPoint,
            _poolToken,
            _rewarder,
            _nftDescriptor,
            _allowPartialWithdrawals
        );
    }

    /**
     * @notice Modify the given pool's properties. Can only be called by an operator.
     * @param _pid The index of the pool. See poolInfo.
     * @param _allocPoint New AP of the pool.
     * @param _rewarder Address of the rewarder delegate.
     * @param _name Name of pool to be displayed in NFT image.
     * @param _nftDescriptor The contract address for NFTDescriptor, which will return the token URI.
     * @param _overwriteRewarder True if _rewarder should be set. Otherwise `rewarder` is ignored.
     */
    function modifyPool(
        uint256 _pid,
        uint256 _allocPoint,
        address _rewarder,
        string calldata _name,
        address _nftDescriptor,
        bool _overwriteRewarder
    ) external override onlyRole(OPERATOR) {
        if (_pid >= poolInfo.length) revert Reliquary__NON_EXISTENT_POOL();

        for (uint256 i_; i_ < poolLength();) {
            _updatePool(i_);
            unchecked {
                ++i_;
            }
        }

        PoolInfo storage pool = poolInfo[_pid];
        uint256 totalAlloc_ = totalAllocPoint + _allocPoint - pool.allocPoint;
        if (totalAlloc_ == 0) revert Reliquary__ZERO_TOTAL_ALLOC_POINT();
        totalAllocPoint = totalAlloc_;
        pool.allocPoint = _allocPoint;

        if (_overwriteRewarder) {
            pool.rewarder = _rewarder;
        }

        pool.name = _name;
        pool.nftDescriptor = _nftDescriptor;

        emit ReliquaryEvents.LogPoolModified(
            _pid, _allocPoint, _overwriteRewarder ? _rewarder : pool.rewarder, _nftDescriptor
        );
    }

    /**
     * @notice Update reward variables for all pools. Be careful of gas spending!
     */
    function massUpdatePools() external override nonReentrant {
        for (uint256 i_; i_ < poolLength();) {
            _updatePool(i_);
            unchecked {
                ++i_;
            }
        }
    }

    /**
     * @notice Update reward variables of the given pool.
     * @param _pid The index of the pool. See poolInfo.
     */
    function updatePool(uint256 _pid) external override nonReentrant {
        _updatePool(_pid);
    }

    /**
     * @notice Deposit pool tokens to Reliquary for reward token allocation.
     * @param _amount Token amount to deposit.
     * @param _relicId NFT ID of the position being deposited to.
     */
    function deposit(uint256 _amount, uint256 _relicId) external override nonReentrant {
        _requireApprovedOrOwner(_relicId);
        _deposit(_amount, _relicId);
    }

    /**
     * @notice Withdraw pool tokens.
     * @param _amount token amount to withdraw.
     * @param _relicId NFT ID of the position being withdrawn.
     */
    function withdraw(uint256 _amount, uint256 _relicId) external override nonReentrant {
        if (_amount == 0) revert Reliquary__ZERO_AMOUNT();
        _requireApprovedOrOwner(_relicId);

        (uint256 poolId,) = _updatePosition(_amount, _relicId, Kind.WITHDRAW, address(0));

        IERC20(poolInfo[poolId].poolToken).safeTransfer(msg.sender, _amount);

        emit ReliquaryEvents.Withdraw(poolId, _amount, msg.sender, _relicId);
    }

    /**
     * @notice Harvest proceeds for transaction sender to owner of Relic `relicId`.
     * @param _relicId NFT ID of the position being harvested.
     * @param _harvestTo Address to send rewards to (zero address if harvest should not be performed).
     */
    function harvest(uint256 _relicId, address _harvestTo) external override nonReentrant {
        _requireApprovedOrOwner(_relicId);

        (uint256 poolId_, uint256 receivedReward_) =
            _updatePosition(0, _relicId, Kind.OTHER, _harvestTo);

        emit ReliquaryEvents.Harvest(poolId_, receivedReward_, _harvestTo, _relicId);
    }

    /**
     * @notice Withdraw pool tokens and harvest proceeds for transaction sender to owner of Relic `relicId`.
     * @param _amount token amount to withdraw.
     * @param _relicId NFT ID of the position being withdrawn and harvested.
     * @param _harvestTo Address to send rewards to (zero address if harvest should not be performed).
     */
    function withdrawAndHarvest(uint256 _amount, uint256 _relicId, address _harvestTo)
        external
        override
        nonReentrant
    {
        if (_amount == 0) revert Reliquary__ZERO_AMOUNT();
        _requireApprovedOrOwner(_relicId);

        (uint256 poolId_, uint256 receivedReward_) =
            _updatePosition(_amount, _relicId, Kind.WITHDRAW, _harvestTo);

        IERC20(poolInfo[poolId_].poolToken).safeTransfer(msg.sender, _amount);

        emit ReliquaryEvents.Withdraw(poolId_, _amount, msg.sender, _relicId);
        emit ReliquaryEvents.Harvest(poolId_, receivedReward_, _harvestTo, _relicId);
    }

    /**
     * @notice Withdraw without caring about rewards. EMERGENCY ONLY.
     * @param _relicId NFT ID of the position to emergency withdraw from and burn.
     */
    function emergencyWithdraw(uint256 _relicId) external override nonReentrant {
        address to_ = ownerOf(_relicId);
        if (to_ != msg.sender) revert Reliquary__NOT_OWNER();

        PositionInfo storage position = positionForId[_relicId];

        uint256 amount_ = position.amount;
        uint256 poolId_ = position.poolId;
        uint256 levelId_ = position.level;

        _updatePool(poolId_);

        poolInfo[poolId_].totalLpSupplied -= amount_ * poolInfo[poolId_].curve.getFunction(levelId_);

        _burn(_relicId);
        delete positionForId[_relicId];

        IERC20(poolInfo[poolId_].poolToken).safeTransfer(to_, amount_);

        emit ReliquaryEvents.EmergencyWithdraw(poolId_, amount_, to_, _relicId);
    }

    /**
     * @notice Update position without performing a deposit/withdraw/harvest.
     * @param _relicId The NFT ID of the position being updated.
     */
    function updatePosition(uint256 _relicId) external override nonReentrant {
        if (!_exists(_relicId)) revert Reliquary__NON_EXISTENT_RELIC();
        _updatePosition(0, _relicId, Kind.OTHER, address(0));
    }

    /// @notice Returns a PositionInfo object for the given relicId.
    function getPositionForId(uint256 _relicId)
        external
        view
        override
        returns (PositionInfo memory position_)
    {
        position_ = positionForId[_relicId];
    }

    /// @notice Returns a PoolInfo object for pool ID `pid`.
    function getPoolInfo(uint256 _pid) public view override returns (PoolInfo memory pool_) {
        pool_ = poolInfo[_pid];
    }

    /**
     * @notice View function to retrieve the relicIds, poolIds, and pendingReward for each Relic owned by an address.
     * @param _owner Address of the owner to retrieve info for.
     * @return pendingRewards_ Array of PendingReward objects.
     */
    function pendingRewardsOfOwner(address _owner)
        external
        view
        override
        returns (PendingReward[] memory pendingRewards_)
    {
        uint256 balance_ = balanceOf(_owner);
        pendingRewards_ = new PendingReward[](balance_);
        for (uint256 i_; i_ < balance_;) {
            uint256 relicId_ = tokenOfOwnerByIndex(_owner, i_);
            pendingRewards_[i_] = PendingReward({
                relicId: relicId_,
                poolId: positionForId[relicId_].poolId,
                pendingReward: pendingReward(relicId_)
            });
            unchecked {
                ++i_;
            }
        }
    }

    /**
     * @notice View function to retrieve owned positions for an address.
     * @param _owner Address of the owner to retrieve info for.
     * @return relicIds_ Each relicId owned by the given address.
     * @return positionInfos_ The PositionInfo object for each relicId.
     */
    function relicPositionsOfOwner(address _owner)
        external
        view
        override
        returns (uint256[] memory relicIds_, PositionInfo[] memory positionInfos_)
    {
        uint256 balance_ = balanceOf(_owner);
        relicIds_ = new uint256[](balance_);
        positionInfos_ = new PositionInfo[](balance_);
        for (uint256 i_; i_ < balance_;) {
            relicIds_[i_] = tokenOfOwnerByIndex(_owner, i_);
            positionInfos_[i_] = positionForId[relicIds_[i_]];
            unchecked {
                ++i_;
            }
        }
    }

    /// @notice Returns whether `_spender` is allowed to manage Relic `_relicId`.
    function isApprovedOrOwner(address _spender, uint256 _relicId)
        external
        view
        override
        returns (bool)
    {
        return _isApprovedOrOwner(_spender, _relicId);
    }

    /**
     * @notice Create a new Relic NFT and deposit into this position.
     * @param _to Address to mint the Relic to.
     * @param _pid The index of the pool. See poolInfo.
     * @param _amount Token amount to deposit.
     */
    function createRelicAndDeposit(address _to, uint256 _pid, uint256 _amount)
        public
        virtual
        override
        nonReentrant
        returns (uint256 id_)
    {
        if (_pid >= poolInfo.length) revert Reliquary__NON_EXISTENT_POOL();
        id_ = _mint(_to);
        positionForId[id_].poolId = _pid;
        _deposit(_amount, id_);
        emit ReliquaryEvents.CreateRelic(_pid, _to, id_);
    }

    /**
     * @notice Split an owned Relic into a new one, while maintaining maturity.
     * @param _fromId The NFT ID of the Relic to split from.
     * @param _amount Amount to move from existing Relic into the new one.
     * @param _to Address to mint the Relic to.
     * @return newId_ The NFT ID of the new Relic.
     */
    function split(uint256 _fromId, uint256 _amount, address _to)
        public
        virtual
        override
        nonReentrant
        returns (uint256 newId_)
    {
        if (_amount == 0) revert Reliquary__ZERO_AMOUNT();
        _requireApprovedOrOwner(_fromId);

        PositionInfo storage fromPosition = positionForId[_fromId];
        uint256 poolId_ = fromPosition.poolId;
        if (!poolInfo[poolId_].allowPartialWithdrawals) {
            revert Reliquary__PARTIAL_WITHDRAWALS_DISABLED();
        }

        uint256 fromAmount_ = fromPosition.amount;
        uint256 newFromAmount_ = fromAmount_ - _amount;
        fromPosition.amount = newFromAmount_;

        newId_ = _mint(_to);
        PositionInfo storage newPosition = positionForId[newId_];
        newPosition.amount = _amount;
        newPosition.entry = fromPosition.entry;
        uint256 level_ = fromPosition.level;
        newPosition.level = level_;
        newPosition.poolId = poolId_;

        uint256 multiplier_ = _updatePool(poolId_) * poolInfo[poolId_].curve.getFunction(level_);
        uint256 pendingFrom_ =
            Math.mulDiv(fromAmount_, multiplier_, ACC_REWARD_PRECISION) - fromPosition.rewardDebt;
        if (pendingFrom_ != 0) {
            fromPosition.rewardCredit += pendingFrom_;
        }

        fromPosition.rewardDebt = Math.mulDiv(newFromAmount_, multiplier_, ACC_REWARD_PRECISION);
        newPosition.rewardDebt = Math.mulDiv(_amount, multiplier_, ACC_REWARD_PRECISION);

        if (poolInfo[poolId_].rewarder != address(0)) {
            IRewarder(poolInfo[poolId_].rewarder).onSplit(
                poolInfo[poolId_].curve, _fromId, newId_, _amount, fromAmount_, level_
            );
        }

        emit ReliquaryEvents.CreateRelic(poolId_, _to, newId_);
        emit ReliquaryEvents.Split(_fromId, newId_, _amount);
    }

    struct LocalVariables_shift {
        uint256 fromAmount;
        uint256 poolId;
        uint256 toAmount;
        uint256 newFromAmount;
        uint256 newToAmount;
        uint256 fromLevel;
        uint256 oldToLevel;
        uint256 newToLevel;
        uint256 accRewardPerShare;
        uint256 fromMultiplier;
        uint256 pendingFrom;
        uint256 pendingTo;
    }

    /**
     * @notice Transfer amount from one Relic into another, updating maturity in the receiving Relic.
     * @param _fromId The NFT ID of the Relic to transfer from.
     * @param _toId The NFT ID of the Relic being transferred to.
     * @param _amount The amount being transferred.
     */
    function shift(uint256 _fromId, uint256 _toId, uint256 _amount)
        public
        virtual
        override
        nonReentrant
    {
        if (_amount == 0) revert Reliquary__ZERO_AMOUNT();
        if (_fromId == _toId) revert Reliquary__DUPLICATE_RELIC_IDS();
        _requireApprovedOrOwner(_fromId);
        _requireApprovedOrOwner(_toId);

        LocalVariables_shift memory vars_;
        PositionInfo storage fromPosition = positionForId[_fromId];
        vars_.poolId = fromPosition.poolId;
        if (!poolInfo[vars_.poolId].allowPartialWithdrawals) {
            revert Reliquary__PARTIAL_WITHDRAWALS_DISABLED();
        }

        PositionInfo storage toPosition = positionForId[_toId];
        if (vars_.poolId != toPosition.poolId) revert Reliquary__RELICS_NOT_OF_SAME_POOL();

        vars_.fromAmount = fromPosition.amount;
        vars_.toAmount = toPosition.amount;
        toPosition.entry = (
            vars_.fromAmount * fromPosition.entry + vars_.toAmount * toPosition.entry
        ) / (vars_.fromAmount + vars_.toAmount);

        vars_.newFromAmount = vars_.fromAmount - _amount;
        fromPosition.amount = vars_.newFromAmount;

        vars_.newToAmount = vars_.toAmount + _amount;
        toPosition.amount = vars_.newToAmount;

        vars_.fromLevel = positionForId[_fromId].level;
        vars_.oldToLevel = positionForId[_toId].level;
        vars_.newToLevel = _updateLevel(_toId, vars_.oldToLevel);

        vars_.accRewardPerShare = _updatePool(vars_.poolId);
        vars_.fromMultiplier =
            vars_.accRewardPerShare * poolInfo[vars_.poolId].curve.getFunction(vars_.fromLevel);
        vars_.pendingFrom = Math.mulDiv(
            vars_.fromAmount, vars_.fromMultiplier, ACC_REWARD_PRECISION
        ) - fromPosition.rewardDebt;
        if (vars_.pendingFrom != 0) {
            fromPosition.rewardCredit += vars_.pendingFrom;
        }
        vars_.pendingTo = Math.mulDiv(
            vars_.toAmount,
            vars_.accRewardPerShare * poolInfo[vars_.poolId].curve.getFunction(vars_.oldToLevel),
            ACC_REWARD_PRECISION
        ) - toPosition.rewardDebt;
        if (vars_.pendingTo != 0) {
            toPosition.rewardCredit += vars_.pendingTo;
        }
        fromPosition.rewardDebt =
            Math.mulDiv(vars_.newFromAmount, vars_.fromMultiplier, ACC_REWARD_PRECISION);
        toPosition.rewardDebt = Math.mulDiv(
            vars_.newToAmount * vars_.accRewardPerShare,
            poolInfo[vars_.poolId].curve.getFunction(vars_.newToLevel),
            ACC_REWARD_PRECISION
        );

        address rewarder_ = poolInfo[vars_.poolId].rewarder;
        if (rewarder_ != address(0)) {
            IRewarder(rewarder_).onShift(
                poolInfo[vars_.poolId].curve,
                _fromId,
                _toId,
                _amount,
                vars_.fromAmount,
                vars_.toAmount,
                vars_.fromLevel,
                vars_.oldToLevel,
                vars_.newToLevel
            );
        }

        _shiftLevelBalances(
            vars_.fromLevel,
            vars_.oldToLevel,
            vars_.newToLevel,
            vars_.poolId,
            _amount,
            vars_.toAmount,
            vars_.newToAmount
        );

        emit ReliquaryEvents.Shift(_fromId, _toId, _amount);
    }

    /**
     * @notice Transfer entire position (including rewards) from one Relic into another, burning it
     * and updating maturity in the receiving Relic.
     * @param _fromId The NFT ID of the Relic to transfer from.
     * @param _toId The NFT ID of the Relic being transferred to.
     */
    function merge(uint256 _fromId, uint256 _toId) public virtual override nonReentrant {
        if (_fromId == _toId) revert Reliquary__DUPLICATE_RELIC_IDS();
        _requireApprovedOrOwner(_fromId);
        _requireApprovedOrOwner(_toId);

        PositionInfo storage fromPosition = positionForId[_fromId];
        uint256 fromAmount_ = fromPosition.amount;

        uint256 poolId_ = fromPosition.poolId;
        PositionInfo storage toPosition = positionForId[_toId];
        if (poolId_ != toPosition.poolId) revert Reliquary__RELICS_NOT_OF_SAME_POOL();

        uint256 toAmount_ = toPosition.amount;
        uint256 newToAmount_ = toAmount_ + fromAmount_;
        if (newToAmount_ == 0) revert Reliquary__MERGING_EMPTY_RELICS();
        toPosition.entry =
            (fromAmount_ * fromPosition.entry + toAmount_ * toPosition.entry) / newToAmount_;

        toPosition.amount = newToAmount_;

        uint256 fromLevel_ = positionForId[_fromId].level;
        uint256 oldToLevel_ = positionForId[_toId].level;
        uint256 newToLevel_ = _updateLevel(_toId, oldToLevel_);

        uint256 accRewardPerShare_ = _updatePool(poolId_);

        // We split the calculation into two mulDiv()'s to minimise the risk of overflow.
        uint256 pendingTo_ = (
            Math.mulDiv(
                fromAmount_,
                accRewardPerShare_ * poolInfo[poolId_].curve.getFunction(fromLevel_),
                ACC_REWARD_PRECISION
            )
                + Math.mulDiv(
                    toAmount_,
                    accRewardPerShare_ * poolInfo[poolId_].curve.getFunction(oldToLevel_),
                    ACC_REWARD_PRECISION
                )
        ) + fromPosition.rewardCredit - fromPosition.rewardDebt - toPosition.rewardDebt;

        if (pendingTo_ != 0) {
            toPosition.rewardCredit += pendingTo_;
        }
        toPosition.rewardDebt = Math.mulDiv(
            newToAmount_,
            accRewardPerShare_ * poolInfo[poolId_].curve.getFunction(newToLevel_),
            ACC_REWARD_PRECISION
        );

        _burn(_fromId);
        delete positionForId[_fromId];

        if (poolInfo[poolId_].rewarder != address(0)) {
            IRewarder(poolInfo[poolId_].rewarder).onMerge(
                poolInfo[poolId_].curve,
                _fromId,
                _toId,
                fromAmount_,
                toAmount_,
                fromLevel_,
                oldToLevel_,
                newToLevel_
            );
        }

        _shiftLevelBalances(
            fromLevel_, oldToLevel_, newToLevel_, poolId_, fromAmount_, toAmount_, newToAmount_
        );

        emit ReliquaryEvents.Merge(_fromId, _toId, fromAmount_);
    }

    /// @notice Burns the Relic with ID `_tokenId`. Cannot be called if there is any principal or rewards in the Relic.
    function burn(uint256 _tokenId) public virtual override(IReliquary, ERC721Burnable) {
        if (positionForId[_tokenId].amount != 0) revert Reliquary__BURNING_PRINCIPAL();
        if (pendingReward(_tokenId) != 0) revert Reliquary__BURNING_REWARDS();
        super.burn(_tokenId);
    }

    /**
     * @notice View function to see pending reward tokens on frontend.
     * @param _relicId ID of the position.
     * @return pending_ reward amount for a given position owner.
     */
    function pendingReward(uint256 _relicId) public view override returns (uint256 pending_) {
        PositionInfo storage position = positionForId[_relicId];
        uint256 poolId_ = position.poolId;
        PoolInfo storage pool = poolInfo[poolId_];
        uint256 accRewardPerShare_ = pool.accRewardPerShare;
        uint256 lpSupply_ = pool.totalLpSupplied;

        uint256 secondsSinceReward_ = block.timestamp - pool.lastRewardTime;
        if (secondsSinceReward_ != 0 && lpSupply_ != 0) {
            uint256 reward_ =
                (secondsSinceReward_ * emissionRate * pool.allocPoint) / totalAllocPoint;
            accRewardPerShare_ += Math.mulDiv(reward_, ACC_REWARD_PRECISION, lpSupply_);
        }

        uint256 leveledAmount_ =
            position.amount * poolInfo[poolId_].curve.getFunction(position.level);
        pending_ = Math.mulDiv(leveledAmount_, accRewardPerShare_, ACC_REWARD_PRECISION)
            + position.rewardCredit - position.rewardDebt;
    }

    /// @notice Returns the number of Reliquary pools.
    function poolLength() public view override returns (uint256 pools_) {
        pools_ = poolInfo.length;
    }

    /**
     * @notice Returns the ERC721 tokenURI given by the pool's NFTDescriptor.
     * @dev Can be gas expensive if used in a transaction and the NFTDescriptor is complex.
     * @param _tokenId The NFT ID of the Relic to get the tokenURI for.
     */
    function tokenURI(uint256 _tokenId) public view override(ERC721) returns (string memory) {
        if (!_exists(_tokenId)) revert Reliquary__NON_EXISTENT_RELIC();
        return INFTDescriptor(poolInfo[positionForId[_tokenId].poolId].nftDescriptor)
            .constructTokenURI(_tokenId);
    }

    /// @dev Implement ERC165 to return which interfaces this contract conforms to
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        virtual
        override(IERC165, AccessControlEnumerable, ERC721, ERC721Enumerable)
        returns (bool)
    {
        return _interfaceId == type(IReliquary).interfaceId || super.supportsInterface(_interfaceId);
    }

    /// @dev Internal `_updatePool` function without nonReentrant modifier.
    function _updatePool(uint256 _pid) internal returns (uint256 accRewardPerShare_) {
        if (_pid >= poolLength()) revert Reliquary__NON_EXISTENT_POOL();
        PoolInfo storage pool = poolInfo[_pid];
        uint256 timestamp_ = block.timestamp;
        uint256 lastRewardTime_ = pool.lastRewardTime;
        uint256 secondsSinceReward_ = timestamp_ - lastRewardTime_;

        accRewardPerShare_ = pool.accRewardPerShare;
        if (secondsSinceReward_ != 0) {
            uint256 lpSupply_ = poolInfo[_pid].totalLpSupplied;

            if (lpSupply_ != 0) {
                uint256 reward_ =
                    (secondsSinceReward_ * emissionRate * pool.allocPoint) / totalAllocPoint;
                accRewardPerShare_ += Math.mulDiv(reward_, ACC_REWARD_PRECISION, lpSupply_);
                pool.accRewardPerShare = accRewardPerShare_;
            }

            pool.lastRewardTime = timestamp_;

            emit ReliquaryEvents.LogUpdatePool(_pid, timestamp_, lpSupply_, accRewardPerShare_);
        }
    }

    /// @dev Internal deposit function that assumes `relicId` is valid.
    function _deposit(uint256 _amount, uint256 _relicId) internal {
        if (_amount == 0) revert Reliquary__ZERO_AMOUNT();

        (uint256 poolId_,) = _updatePosition(_amount, _relicId, Kind.DEPOSIT, address(0));

        IERC20(poolInfo[poolId_].poolToken).safeTransferFrom(msg.sender, address(this), _amount);

        emit ReliquaryEvents.Deposit(poolId_, _amount, ownerOf(_relicId), _relicId);
    }

    struct LocalVariables_updatePosition {
        uint256 accRewardPerShare;
        uint256 oldAmount;
        uint256 newAmount;
        uint256 oldLevel;
        uint256 newLevel;
        bool harvest;
    }

    /**
     * @dev Internal function called whenever a position's state needs to be modified.
     * @param _amount Amount of poolToken to deposit/withdraw.
     * @param _relicId The NFT ID of the position being updated.
     * @param _kind Indicates whether tokens are being added to, or removed from, a pool.
     * @param _harvestTo Address to send rewards to (zero address if harvest should not be performed).
     * @return poolId_ Pool ID of the given position.
     * @return received_ Amount of reward token dispensed to `_harvestTo` on harvest.
     */
    function _updatePosition(uint256 _amount, uint256 _relicId, Kind _kind, address _harvestTo)
        internal
        returns (uint256 poolId_, uint256 received_)
    {
        LocalVariables_updatePosition memory vars_;
        PositionInfo storage position = positionForId[_relicId];
        poolId_ = position.poolId;
        vars_.accRewardPerShare = _updatePool(poolId_);

        vars_.oldAmount = position.amount;
        if (_kind == Kind.DEPOSIT) {
            _updateEntry(_amount, _relicId);
            vars_.newAmount = vars_.oldAmount + _amount;
            position.amount = vars_.newAmount;
        } else if (_kind == Kind.WITHDRAW) {
            if (_amount != vars_.oldAmount && !poolInfo[poolId_].allowPartialWithdrawals) {
                revert Reliquary__PARTIAL_WITHDRAWALS_DISABLED();
            }
            vars_.newAmount = vars_.oldAmount - _amount;
            position.amount = vars_.newAmount;
        } else {
            vars_.newAmount = vars_.oldAmount;
        }

        vars_.oldLevel = position.level;
        vars_.newLevel = _updateLevel(_relicId, vars_.oldLevel);

        uint256 pendingReward_ = Math.mulDiv(
            vars_.oldAmount,
            poolInfo[poolId_].curve.getFunction(vars_.oldLevel) * vars_.accRewardPerShare,
            ACC_REWARD_PRECISION
        ) - position.rewardDebt;
        position.rewardDebt = Math.mulDiv(
            vars_.newAmount,
            poolInfo[poolId_].curve.getFunction(vars_.newLevel) * vars_.accRewardPerShare,
            ACC_REWARD_PRECISION
        );

        vars_.harvest = _harvestTo != address(0);
        if (!vars_.harvest && pendingReward_ != 0) {
            position.rewardCredit += pendingReward_;
        } else if (vars_.harvest) {
            uint256 total = pendingReward_ + position.rewardCredit;
            received_ = _receivedReward(total);
            position.rewardCredit = total - received_;
            if (received_ != 0) {
                IERC20(rewardToken).safeTransfer(_harvestTo, received_);
            }
            address rewarder_ = poolInfo[poolId_].rewarder;
            if (rewarder_ != address(0)) {
                IRewarder(rewarder_).onReward(
                    poolInfo[poolId_].curve,
                    _relicId,
                    received_,
                    _harvestTo,
                    vars_.oldAmount,
                    vars_.oldLevel,
                    vars_.newLevel
                );
            }
        }

        if (_kind == Kind.DEPOSIT) {
            address rewarder_ = poolInfo[poolId_].rewarder;
            if (rewarder_ != address(0)) {
                IRewarder(rewarder_).onDeposit(
                    poolInfo[poolId_].curve,
                    _relicId,
                    _amount,
                    vars_.oldAmount,
                    vars_.oldLevel,
                    vars_.newLevel
                );
            }
        } else if (_kind == Kind.WITHDRAW) {
            address rewarder_ = poolInfo[poolId_].rewarder;
            if (rewarder_ != address(0)) {
                IRewarder(rewarder_).onWithdraw(
                    poolInfo[poolId_].curve,
                    _relicId,
                    _amount,
                    vars_.oldAmount,
                    vars_.oldLevel,
                    vars_.newLevel
                );
            }
        }

        if (vars_.oldLevel != vars_.newLevel) {
            poolInfo[poolId_].totalLpSupplied -=
                vars_.oldAmount * poolInfo[poolId_].curve.getFunction(vars_.oldLevel);
            poolInfo[poolId_].totalLpSupplied +=
                vars_.newAmount * poolInfo[poolId_].curve.getFunction(vars_.newLevel);
        } else if (_kind == Kind.DEPOSIT) {
            poolInfo[poolId_].totalLpSupplied +=
                _amount * poolInfo[poolId_].curve.getFunction(vars_.oldLevel);
        } else if (_kind == Kind.WITHDRAW) {
            poolInfo[poolId_].totalLpSupplied -=
                _amount * poolInfo[poolId_].curve.getFunction(vars_.oldLevel);
        }
    }

    /**
     * @notice Updates the user's entry time based on the weight of their deposit or withdrawal.
     * @param _amount The amount of the deposit / withdrawal.
     * @param _relicId The NFT ID of the position being updated.
     */
    function _updateEntry(uint256 _amount, uint256 _relicId) internal {
        PositionInfo storage position = positionForId[_relicId];
        uint256 amountBefore_ = position.amount;
        if (amountBefore_ == 0) {
            position.entry = block.timestamp;
        } else {
            uint256 entryBefore_ = position.entry;
            uint256 maturity_ = block.timestamp - entryBefore_;
            position.entry = entryBefore_ + (maturity_ * _findWeight(_amount, amountBefore_)) / 1e12;
        }
    }

    /**
     * @notice Updates the position's level based on entry time.
     * @param _relicId The NFT ID of the position being updated.
     * @param _oldLevel Level of position before update.
     * @return newLevel_ Level of position after update.
     */
    function _updateLevel(uint256 _relicId, uint256 _oldLevel)
        internal
        returns (uint256 newLevel_)
    {
        newLevel_ = block.timestamp - positionForId[_relicId].entry;
        if (_oldLevel != newLevel_) {
            positionForId[_relicId].level = newLevel_;
            emit ReliquaryEvents.LevelChanged(_relicId, newLevel_);
        }
    }

    /// @dev Ensure the behavior of ERC721Enumerable _beforeTokenTransfer is preserved.
    function _beforeTokenTransfer(address _from, address _to, uint256 _tokenId, uint256 _batchSize)
        internal
        override(ERC721, ERC721Enumerable)
    {
        ERC721Enumerable._beforeTokenTransfer(_from, _to, _tokenId, _batchSize);
    }

    /**
     * @notice Calculate how much the owner will actually receive on harvest, given available reward tokens.
     * @param _pendingReward Amount of reward token owed.
     * @return received_ The minimum between amount owed and amount available.
     */
    function _receivedReward(uint256 _pendingReward) internal view returns (uint256 received_) {
        uint256 available_ = IERC20(rewardToken).balanceOf(address(this));
        received_ = (available_ > _pendingReward) ? _pendingReward : available_;
    }

    /**
     * @notice Require the sender is either the owner of the Relic or approved to transfer it.
     * @param _relicId The NFT ID of the Relic.
     */
    function _requireApprovedOrOwner(uint256 _relicId) internal view {
        if (!_isApprovedOrOwner(msg.sender, _relicId)) revert Reliquary__NOT_APPROVED_OR_OWNER();
    }

    /**
     * @notice Used in `_updateEntry` to find weights without any underflows or zero division problems.
     * @param _addedValue New value being added.
     * @param _oldValue Current amount of x.
     */
    function _findWeight(uint256 _addedValue, uint256 _oldValue)
        internal
        pure
        returns (uint256 weightNew_)
    {
        if (_oldValue < _addedValue) {
            weightNew_ = 1e12 - (_oldValue * 1e12) / (_addedValue + _oldValue);
        } else if (_addedValue < _oldValue) {
            weightNew_ = (_addedValue * 1e12) / (_addedValue + _oldValue);
        } else {
            weightNew_ = 5e11;
        }
    }

    /// @dev Handle updating balances for each affected tranche when shifting and merging.
    function _shiftLevelBalances(
        uint256 _fromLevel,
        uint256 _oldToLevel,
        uint256 _newToLevel,
        uint256 _poolId,
        uint256 _amount,
        uint256 _toAmount,
        uint256 _newToAmount
    ) private {
        PoolInfo storage pool = poolInfo[_poolId];

        if (_fromLevel != _newToLevel) {
            pool.totalLpSupplied -= _amount * pool.curve.getFunction(_fromLevel);
        }
        if (_oldToLevel != _newToLevel) {
            pool.totalLpSupplied -= _toAmount * pool.curve.getFunction(_oldToLevel);
        }

        if (_fromLevel != _newToLevel && _oldToLevel != _newToLevel) {
            pool.totalLpSupplied += _newToAmount * pool.curve.getFunction(_newToLevel);
        } else if (_fromLevel != _newToLevel) {
            pool.totalLpSupplied += _amount * pool.curve.getFunction(_newToLevel);
        } else if (_oldToLevel != _newToLevel) {
            pool.totalLpSupplied += _toAmount * pool.curve.getFunction(_newToLevel);
        }
    }

    /// @dev Increments the ID nonce and mints a new Relic to `to`.
    function _mint(address _to) private returns (uint256 id_) {
        id_ = ++idNonce;
        _safeMint(_to, id_);
    }
}
