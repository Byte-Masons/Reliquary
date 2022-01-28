// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

import "./Relic.sol";
import "./interfaces/ICurve.sol";
import "./interfaces/IRewarder.sol";
import "./libraries/SignedSafeMath.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// TODO tess3rac7 can consider migrating from Ownable to AccessControl

/*
 + NOTE: Maybe make BASE_OATH_PER_BLOCK an upgradable function call so we can curve that too
 + NOTE: Add UniV3's NFT metadata standard so marketplace frontends can return json data
 + NOTE: Work on quality of life abstractions and position management
*/

/*
 + @title Reliquary
 + @author Justin Bebis, Zokunei & the Byte Masons team
 + @notice Built on the MasterChefV2 system authored by Sushi's team
 +
 + // TODO tess3rac7 need some more ELI5 here. Define "position," "maturity" first
 +
 + @notice This system is designed to modify Masterchef accounting logic such that
 + behaviors can be programmed on a per-pool basis using a curve library, which
 + modifies emissions based on position maturity and binds it to the base rate
 + using a per-token aggregated average
 +
 + // TODO tess3rac7 "position" used in two different contexts below, reconcile
 +
 + @notice Deposits are tracked by position instead of by user, and mapped to an individual
 + NFT as opposed to an Externally Owned Account (EOA). This allows for increased composability without
 + affecting accounting logic too much, and users can exit their position without withdrawing
 + their liquidity oShriner sacrificing their position's maturity.
 +
 + // TODO tess3rac7 typo above ^ needs fixing
*/
contract Reliquary is Relic, Ownable, Multicall, ReentrancyGuard {
    using SignedSafeMath for int256;
    using SafeERC20 for IERC20;

    // TODO tess3rac7 is there a better term than PositionInfo? RelicInfo?
    /*
     + @notice Info for each Reliquary position.
     + `amount` LP token amount the position owner has provided.
     + `rewardDebt` The amount of OATH entitled to the position owner.
     + `entry` Used to determine the entry of the position
    */
    struct PositionInfo {
        uint256 amount;
        int256 rewardDebt;
        uint256 entry; // position owner's relative entry into the pool.
    }

    /*
     + @notice Info of each Reliquary pool
     + `accOathPerShare` Accumulated OATH per share of pool (1 / 1e12)
     + `lastRewardTime` Last timestamp the accumulated OATH was updated
     + `allocPoint` pool's individual allocation - ratio of the total allocation
     + `averageEntry` average entry time of each share, used to determine pool maturity
     + `curveAddress` math library used to curve emissions
    */
    struct PoolInfo {
        uint256 accOathPerShare;
        uint256 lastRewardTime;
        uint256 allocPoint;
        uint256 averageEntry;
        address curveAddress;
    }

    /*
     + @notice used to determine position's emission modifier
     + `param` distance the % distance the position is from the curve, in base 10000
     + `param` placement flag to note whether position is above or below the average maturity
    */
    // TODO tess3rac7 this could also use a rename
    struct Position {
        uint256 distance;
        Placement placement;
    }

    // @notice used to determine whether a position is above or below the average curve
    enum Placement {
        ABOVE,
        BELOW
    }

    // @notice used to determine whether the average entry is increased or decreased
    enum Kind {
        DEPOSIT,
        WITHDRAW
    }

    /// @notice Address of OATH contract.
    IERC20 public immutable OATH;
    /// @notice Info of each MCV2 pool.
    PoolInfo[] public poolInfo;
    /// @notice Address of the LP token for each MCV2 pool.
    IERC20[] public lpToken;
    /// @notice Address of each `IRewarder` contract in MCV2.
    IRewarder[] public rewarder;

    /// @notice Info of each staked position
    mapping(uint256 => mapping(uint256 => PositionInfo)) public positionInfo;
    // TODO tess3rac7 maybe rename this mapping as well..

    /// @notice ensures the same token isn't added to the contract twice
    mapping(address => bool) public hasBeenAdded;

    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    uint256 private constant EMISSIONS_PER_MILLISECOND = 1e8;
    uint256 private constant ACC_OATH_PRECISION = 1e12;
    uint256 private constant BASIS_POINTS = 10_000;

    event Deposit(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        address indexed to,
        uint256 positionId // TODO tess3rac7 can rename as well (if we rename positionId to nftId)
    );
    event Withdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        address indexed to,
        uint256 positionId // TODO tess3rac7 can rename as well (if we rename positionId to nftId)
    );
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        address indexed to,
        uint256 positionId // TODO tess3rac7 can rename as well (if we rename positionId to nftId)
    );
    event Harvest(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        uint256 positionId // TODO tess3rac7 can rename as well (if we rename positionId to nftId)
    );
    event LogPoolAddition(
        uint256 pid,
        uint256 allocPoint,
        IERC20 indexed lpToken,
        IRewarder indexed rewarder,
        address indexed curve
    );
    event LogPoolModified(uint256 indexed pid, uint256 allocPoint, IRewarder indexed rewarder, address indexed curve);
    event LogUpdatePool(uint256 indexed pid, uint256 lastRewardTime, uint256 lpSupply, uint256 accOathPerShare);
    event LogInit();

    /// @param _oath The OATH token contract address.
    constructor(IERC20 _oath) {
        OATH = _oath;
    }

    // todo jaetask We should rename "MCV2" here, this is the first time this term is used to describe a Pool
    /// @notice Returns the number of MCV2 pools.
    function poolLength() public view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    /*
     + @notice Add a new pool for the specified LP.
     +         Can only be called by the owner.
     +
     + @param _allocPoint the allocation points for the new pool
     + @param _lpToken address of the pooled ERC-20 token
     + @param _rewarder Address of the rewarder delegate
     + @param _curve ICurve // todo description of a curve
    */
    function addPool(
        uint256 _allocPoint,
        IERC20 _lpToken, // todo jaetask if we also accept single tokens here, the variable should not be called _lpToken
        IRewarder _rewarder,
        ICurve _curve
    ) public onlyOwner {
        require(!hasBeenAdded[address(_lpToken)], "this token has already been added");
        require(_lpToken != OATH, "same token");

        totalAllocPoint += _allocPoint;
        lpToken.push(_lpToken);
        rewarder.push(_rewarder);

        poolInfo.push(
            PoolInfo({
                allocPoint: _allocPoint,
                lastRewardTime: _timestamp(),
                accOathPerShare: 0,
                averageEntry: 0,
                curveAddress: address(_curve)
            })
        );
        hasBeenAdded[address(_lpToken)] = true;

        emit LogPoolAddition((lpToken.length - 1), _allocPoint, _lpToken, _rewarder, address(_curve));
    }

    /*
     + @notice Modify the given pool's properties.
     +         Can only be called by the owner.
     +
     + @param _pid The index of the pool. See `poolInfo`.
     + @param _allocPoint New AP of the pool.
     + @param _rewarder Address of the rewarder delegate.
     + @param _curve Address of the curve library
     + @param _shouldOverwriteRewarder True if _rewarder should be set. Otherwise `_rewarder` is ignored.
     + @param _shouldOverwriteCurve True if _curve should be set. Otherwise `_curve` is ignored.
    */
    function modifyPool(
        uint256 _pid,
        uint256 _allocPoint,
        IRewarder _rewarder,
        ICurve _curve,
        bool _shouldOverwriteRewarder,
        bool _shouldOverwriteCurve
    ) public onlyOwner {
        require(_pid < poolInfo.length, "set: pool does not exist");

        totalAllocPoint -= poolInfo[_pid].allocPoint;
        totalAllocPoint += _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;

        if (_shouldOverwriteRewarder) {
            rewarder[_pid] = _rewarder;
        }

        if (_shouldOverwriteCurve) {
            poolInfo[_pid].curveAddress = address(_curve);
        }

        emit LogPoolModified(
            _pid,
            _allocPoint,
            _shouldOverwriteRewarder ? _rewarder : rewarder[_pid],
            _shouldOverwriteCurve ? address(_curve) : poolInfo[_pid].curveAddress
        );
    }

    /*
     + @notice View function to see pending OATH on frontend.
     + @param _pid The index of the pool. See `poolInfo`.
     + @param _positionId ID of the position.
     + @return pending OATH reward for a given position owner.
    */
    // TODO tess3rac7 rename positionId above and below as well accordingly
    function pendingOath(uint256 _pid, uint256 _positionId) external view returns (uint256 pending) {
        PositionInfo storage position = positionInfo[_pid][_positionId];

        PoolInfo storage pool = poolInfo[_pid];
        uint256 accOathPerShare = pool.accOathPerShare;
        uint256 lpSupply = _poolBalance(_pid);

        uint256 millisSinceReward = _timestamp() - pool.lastRewardTime;
        if (millisSinceReward != 0 && lpSupply != 0) {
            uint256 oathReward = (millisSinceReward * EMISSIONS_PER_MILLISECOND * pool.allocPoint) / totalAllocPoint;
            accOathPerShare += (oathReward * ACC_OATH_PRECISION) / lpSupply;
        }

        int256 rawPending = int256((position.amount * accOathPerShare) / ACC_OATH_PRECISION) - position.rewardDebt;
        pending = _calculateEmissions(rawPending.toUInt256(), _positionId, _pid);
    }

    /*
     + @notice Update reward variables for all pools. Be careful of gas spending!
     + @param _poolIds Pool IDs of all to be updated. Make sure to update all active pools.
    */
    function massUpdatePools(uint256[] calldata _poolIds) external {
        for (uint256 i = 0; i < _poolIds.length; i++) {
            updatePool(_poolIds[i]);
        }
    }

    /*
     + @notice Update reward variables of the given pool.
     + @param _pid The index of the pool. See `poolInfo`.
     + @return pool Returns the pool that was updated.
    */
    function updatePool(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 millisSinceReward = _timestamp() - pool.lastRewardTime;

        if (millisSinceReward != 0) {
            uint256 lpSupply = _poolBalance(_pid);

            if (lpSupply != 0) {
                uint256 oathReward = (millisSinceReward * EMISSIONS_PER_MILLISECOND * pool.allocPoint) /
                    totalAllocPoint;
                pool.accOathPerShare += (oathReward * ACC_OATH_PRECISION) / lpSupply;
            }

            pool.lastRewardTime = _timestamp();

            emit LogUpdatePool(_pid, pool.lastRewardTime, lpSupply, pool.accOathPerShare);
        }
    }

    // TODO tess3rac7 "createRelicAndDeposit"?
    function createPositionAndDeposit(
        address _to,
        uint256 _pid,
        uint256 _amount
    ) public returns (uint256 id) {
        id = mint(_to);
        deposit(_pid, _amount, id);
    }

    /*
     + @notice Deposit LP tokens to Reliquary for OATH allocation.
     + @param _pid The index of the pool. See `poolInfo`.
     + @param _amount token amount to deposit.
     + @param _positionId NFT ID of the receiver of `_amount` deposit benefit.
    */
    // Q: TODO tess3rac7 this should still be public?
    // A: for now since same relic for multiple pools, but will update
    function deposit(
        uint256 _pid,
        uint256 _amount,
        uint256 _positionId
    ) public {
        require(_amount != 0, "depositing 0 amount");
        updatePool(_pid);
        _updateEntry(_pid, _amount, _positionId);
        _updateAverageEntry(_pid, _amount, Kind.DEPOSIT);

        PoolInfo storage pool = poolInfo[_pid];
        PositionInfo storage position = positionInfo[_pid][_positionId];
        address to = ownerOf(_positionId);

        position.amount += _amount;
        position.rewardDebt += int256((_amount * pool.accOathPerShare) / ACC_OATH_PRECISION);

        IRewarder _rewarder = rewarder[_pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onOathReward(_pid, to, to, 0, position.amount);
        }

        lpToken[_pid].safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, _pid, _amount, to, _positionId);
    }

    /*
     + @notice Withdraw LP tokens from Reliquary.
     + @param _pid The index of the pool. See `poolInfo`.
     + @param _amount LP token amount to withdraw.
     + @param _positionId NFT ID of the receiver of the tokens.
    */
    // todo jaetask inconsistent variable naming convention, should be `_<someName>`
    function withdraw(
        uint256 _pid,
        uint256 _amount,
        uint256 _positionId
    ) public {
        address to = ownerOf(_positionId);
        require(to == msg.sender, "you do not own this position");
        require(_amount != 0, "withdrawing 0 amount");

        updatePool(_pid);

        PoolInfo storage pool = poolInfo[_pid];
        PositionInfo storage position = positionInfo[_pid][_positionId];

        // Effects
        position.rewardDebt -= int256((_amount * pool.accOathPerShare) / ACC_OATH_PRECISION);
        position.amount -= _amount;
        _updateEntry(_pid, _amount, _positionId);
        _updateAverageEntry(_pid, _amount, Kind.WITHDRAW);

        // Interactions
        IRewarder _rewarder = rewarder[_pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onOathReward(_pid, msg.sender, to, 0, position.amount);
        }

        lpToken[_pid].safeTransfer(to, _amount);

        emit Withdraw(msg.sender, _pid, _amount, to, _positionId);
    }

    /*
     + @notice Harvest proceeds for transaction sender to owner of `_positionId`.
     + @param _pid The index of the pool. See `poolInfo`.
     + @param _positionId NFT ID of the receiver of OATH rewards.
    */
    function harvest(uint256 _pid, uint256 _positionId) public {
        address to = ownerOf(_positionId);
        require(to == msg.sender, "you do not own this position");

        updatePool(_pid);

        PoolInfo storage pool = poolInfo[_pid];
        PositionInfo storage position = positionInfo[_pid][_positionId];

        int256 accumulatedOath = int256((position.amount * pool.accOathPerShare) / ACC_OATH_PRECISION);
        uint256 _pendingOath = (accumulatedOath - position.rewardDebt).toUInt256();
        uint256 _curvedOath = _calculateEmissions(_pendingOath, _positionId, _pid);

        // Effects
        position.rewardDebt = accumulatedOath;

        // Interactions
        if (_curvedOath != 0) {
            OATH.safeTransfer(to, _curvedOath);
        }

        IRewarder _rewarder = rewarder[_pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onOathReward(_pid, msg.sender, to, _curvedOath, position.amount);
        }

        emit Harvest(msg.sender, _pid, _curvedOath, _positionId);
    }

    /*
     + @notice Withdraw LP tokens and harvest proceeds for transaction sender to owner of `_positionId`.
     + @param _pid The index of the pool. See `poolInfo`.
     + @param amount token amount to withdraw.
     + @param _positionId NFT ID of the receiver of the tokens and OATH rewards.
    */
    function withdrawAndHarvest(
        uint256 _pid,
        uint256 amount,
        uint256 _positionId
    ) public {
        address to = ownerOf(_positionId);
        require(to == msg.sender, "you do not own this position");
        require(amount != 0, "withdrawing 0 amount");

        updatePool(_pid);

        PoolInfo storage pool = poolInfo[_pid];
        PositionInfo storage position = positionInfo[_pid][_positionId];
        int256 accumulatedOath = int256((position.amount * pool.accOathPerShare) / ACC_OATH_PRECISION);
        uint256 _pendingOath = (accumulatedOath - position.rewardDebt).toUInt256();
        uint256 _curvedOath = _calculateEmissions(_pendingOath, _positionId, _pid);

        if (_curvedOath != 0) {
            OATH.safeTransfer(to, _curvedOath);
        }

        position.rewardDebt = accumulatedOath - int256((amount * pool.accOathPerShare) / ACC_OATH_PRECISION);
        position.amount -= amount;
        _updateEntry(_pid, amount, _positionId);
        _updateAverageEntry(_pid, amount, Kind.WITHDRAW);

        IRewarder _rewarder = rewarder[_pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onOathReward(_pid, msg.sender, to, _curvedOath, position.amount);
        }

        lpToken[_pid].safeTransfer(to, amount);

        emit Withdraw(msg.sender, _pid, amount, to, _positionId);
        emit Harvest(msg.sender, _pid, _curvedOath, _positionId);
    }

    /*
     + @notice Withdraw without caring about rewards. EMERGENCY ONLY.
     + @param _pid The index of the pool. See `poolInfo`.
     + @param _positionId NFT ID of the receiver of the tokens.
    */
    function emergencyWithdraw(uint256 _pid, uint256 _positionId) public nonReentrant {
        address to = ownerOf(_positionId);
        require(to == msg.sender, "you do not own this position");

        PositionInfo storage position = positionInfo[_pid][_positionId];
        uint256 amount = position.amount;

        position.amount = 0;
        position.rewardDebt = 0;
        _updateEntry(_pid, amount, _positionId);
        _updateAverageEntry(_pid, amount, Kind.WITHDRAW);

        IRewarder _rewarder = rewarder[_pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onOathReward(_pid, msg.sender, to, 0, 0);
        }

        // Note: transfer can fail or succeed if `amount` is zero.
        lpToken[_pid].safeTransfer(to, amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount, to, _positionId);
    }

    /*
     + @notice pulls MasterChef data and passes it to the curve library
     + @param _pid The index of the pool. See `poolInfo`.
     + @param _positionId - the position whose maturity curve you'd like to see
    */

    function curved(uint256 _pid, uint256 _positionId) public view returns (uint256 _curved) {
        PositionInfo storage position = positionInfo[_pid][_positionId];
        PoolInfo memory pool = poolInfo[_pid];

        uint256 maturity = _timestamp() - position.entry;

        _curved = ICurve(pool.curveAddress).curve(maturity);
    }

    /*
     + @notice operates on the position's MasterChef emissions
     + @param amount OATH amount to modify
     + @param _positionId the position that's being modified
     + @param _pid The index of the pool. See `poolInfo`.
    */

    function _calculateEmissions(
        uint256 amount,
        uint256 _positionId,
        uint256 _pid
    ) internal view returns (uint256 emissions) {
        (uint256 distance, Placement placement) = _calculateDistanceFromMean(_positionId, _pid);

        if (placement == Placement.ABOVE) {
            emissions = (amount * (BASIS_POINTS + distance)) / BASIS_POINTS;
        } else if (placement == Placement.BELOW) {
            emissions = (amount * (BASIS_POINTS - distance)) / BASIS_POINTS;
        } else {
            emissions = amount;
        }
    }

    /*
     + @notice calculates how far the user's position maturity is from the average
     + @param _positionId NFT ID of the position being assessed
     + @param _pid The index of the pool. See `poolInfo`.
    */

    function _calculateDistanceFromMean(uint256 _positionId, uint256 _pid)
        internal
        view
        returns (uint256 distance, Placement placement)
    {
        uint256 position = curved(_pid, _positionId);
        uint256 mean = _calculateMean(_pid);

        if (position < mean) {
            distance = ((mean - position) * BASIS_POINTS) / mean;
            placement = Placement.BELOW;
        } else {
            distance = ((position - mean) * BASIS_POINTS) / mean;
            placement = Placement.ABOVE;
        }
    }

    /*
     + @notice calculates the average position of every token on the curve
     + @param _pid The index of the pool. See `poolInfo`.
     + @return the Y value based on X maturity in the context of the curve
    */

    function _calculateMean(uint256 _pid) internal view returns (uint256 mean) {
        PoolInfo memory pool = poolInfo[_pid];
        uint256 maturity = _timestamp() - pool.averageEntry;
        mean = ICurve(pool.curveAddress).curve(maturity);
    }

    /*
     + @notice updates the average entry time of each token in the pool
     + @param _pid The index of the pool. See `poolInfo`.
     + @param amount the amount of tokens being accounted for
     + @param kind the action being performed (deposit / withdrawal)
    */

    function _updateAverageEntry(
        uint256 _pid,
        uint256 amount,
        Kind kind
    ) internal returns (bool success) {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 lpSupply = _poolBalance(_pid);
        if (lpSupply == 0) {
            pool.averageEntry = _timestamp();
            return true;
        } else {
            uint256 weight = (amount * 1e18) / lpSupply;
            uint256 maturity = _timestamp() - pool.averageEntry;
            if (kind == Kind.DEPOSIT) {
                pool.averageEntry += ((maturity * weight) / 1e18);
            } else {
                pool.averageEntry -= ((maturity * weight) / 1e18);
            }
            return true;
        }
    }

    /*
     + @notice updates the user's entry time based on the weight of their deposit or withdrawal
     + @param _pid The index of the pool. See `poolInfo`.
     + @param amount the amount of the deposit / withdrawal
     + @param _positionId the NFT ID of the position being updated
    */

    function _updateEntry(
        uint256 _pid,
        uint256 amount,
        uint256 _positionId
    ) internal returns (bool success) {
        PositionInfo storage position = positionInfo[_pid][_positionId];
        if (position.amount == 0) {
            position.entry = _timestamp();
            return true;
        }
        uint256 weight = (amount * BASIS_POINTS) / position.amount;
        uint256 maturity = _timestamp() - position.entry;
        position.entry += ((maturity * weight) / BASIS_POINTS);
        return true;
    }

    /*
     + @notice returns the total deposits of the pool's token
     + @param _pid The index of the pool. See `poolInfo`.
     + @return the amount of pool tokens held by the contract
    */

    function _poolBalance(uint256 _pid) internal view returns (uint256 total) {
        total = IERC20(lpToken[_pid]).balanceOf(address(this));
    }

    // Converting timestamp to milliseconds so precision isn't lost when we mutate the
    // user's entry time.

    function _timestamp() internal view returns (uint256 timestamp) {
        timestamp = block.timestamp * 1000;
    }
}
