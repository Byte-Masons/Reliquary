// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import 'contracts/Reliquary.sol';
import 'contracts/interfaces/IReliquary.sol';
import 'contracts/rewarders/ParentRewarder.sol';
import './mocks/ERC20Mock.sol';
import 'contracts/nft_descriptors/NFTDescriptorPair.sol';
import 'lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';
import "contracts/curves/Curves.sol";
import "contracts/curves/functions/LinearFunction.sol";
import "contracts/curves/functions/LinearPlateauFunction.sol";

// The only unfuzzed method is reliquary.setEmissionRate()
contract User {
    function proxy(
        address target,
        bytes memory data
    ) public returns (bool success, bytes memory err) {
        return target.call(data);
    }

    function approveERC20(ERC20 target, address spender) public {
        target.approve(spender, type(uint256).max);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

struct DepositData {
    uint relicId;
    uint amount;
    bool isInit;
}

contract ReliquaryProperties {
    // Linear function config (to config)
    uint256 public slope = 1; // Increase of multiplier every second
    uint256 public minMultiplier = 365 days * 100; // Arbitrary (but should be coherent with slope)
    uint256 plateau = 10 days;

    uint public emissionRate = 1e18;
    uint public initialMint = 100 ether;
    uint public constant ACC_REWARD_PRECISION = 1e12;
    uint public immutable startTimestamp;

    uint public totalNbPools;
    uint public totalNbUsers;
    mapping(uint => bool) public isInit;

    uint[] public relicIds;
    uint[] public poolIds;
    User[] public users;
    ERC20Mock[] public tokenPoolIds;
    uint public rewardLostByEmergencyWithdraw;

    ERC20Mock public rewardToken;
    Reliquary public reliquary;
    NFTDescriptor public nftDescriptor;
    Curves curve;
    LinearFunction linearFunction;
    LinearPlateauFunction linearPlateauFunction;

    event LogUint(uint256 a);

    constructor() payable {
        // config -----------
        totalNbUsers = 10; // fix
        totalNbPools = 2; // the fuzzer can add new pools
        // ------------------

        startTimestamp = block.timestamp;
        /// setup reliquary
        rewardToken = new ERC20Mock('OATH Token', 'OATH');
        reliquary = new Reliquary(
            address(rewardToken),
            emissionRate,
            'Relic',
            'NFT'
        );
        nftDescriptor = new NFTDescriptor(address(reliquary));

        linearFunction = new LinearFunction(slope, minMultiplier);
        linearPlateauFunction = new LinearPlateauFunction(slope, minMultiplier, plateau);
        curve = new Curves(linearFunction);
        
        rewardToken.mint(address(reliquary), 100 ether); // provide rewards to reliquary contract

        /// setup token pool
        for (uint i = 0; i < totalNbPools; i++) {
            ERC20Mock token = new ERC20Mock('Pool Token', 'PT');
            tokenPoolIds.push(token);

            // no rewarder for now
            reliquary.addPool(
                100,
                address(token),
                address(0),
                curve,
                'reaper',
                address(nftDescriptor),
                true
            );
            poolIds.push(i);
        }

        /// setup users
        // admin is this contract
        reliquary.grantRole(keccak256('DEFAULT_ADMIN_ROLE'), address(this));
        reliquary.grantRole(keccak256('OPERATOR'), address(this));
        reliquary.grantRole(keccak256('EMISSION_RATE'), address(this));

        for (uint i = 0; i < totalNbUsers; i++) {
            User user = new User();
            users.push(user);
            for (uint j = 0; j < tokenPoolIds.length; j++) {
                tokenPoolIds[j].mint(address(user), initialMint);
                user.approveERC20(tokenPoolIds[j], address(reliquary));
            }
        }
    }

    // --------------------- state updates ---------------------

    /// random add pool
    function randAddPools(
        uint allocPoint,
        uint randSpacingMul,
        uint randSizeMul,
        uint randSpacingMat,
        uint randSizeMat
    ) public {
        uint maxSize = 10;
        require(allocPoint > 0);
        uint startPoolIdsLen = poolIds.length;
        ERC20Mock token = new ERC20Mock('Pool Token', 'PT');
        tokenPoolIds.push(token);

        // no rewarder for now
        reliquary.addPool(
            allocPoint % 10000 ether, // to avoid overflow on totalAllocPoint [0, 10000e18]
            address(token),
            address(0),
            curve,
            'reaper',
            address(nftDescriptor),
            true
        );
        poolIds.push(startPoolIdsLen);
        totalNbPools++;

        // mint new token and setup allowance for users
        for (uint i = 0; i < totalNbUsers; i++) {
            User user = users[i];
            for (uint j = startPoolIdsLen; j < tokenPoolIds.length; j++) {
                tokenPoolIds[j].mint(address(user), initialMint);
                user.approveERC20(tokenPoolIds[j], address(reliquary));
            }
        }
    }

    /// random modify pool
    function randModifyPools(uint randPoolId, uint allocPoint) public {
        reliquary.modifyPool(
            randPoolId % totalNbPools,
            allocPoint % 10000 ether, // to avoid overflow on totalAllocPoint [0, 10000e18]
            address(0),
            'reaper',
            address(nftDescriptor),
            true
        );
    }

    /// random user create relic and deposit
    function randCreateRelicAndDeposit(uint randUser, uint randPool, uint randAmt) public {
        User user = users[randUser % users.length];
        uint amount = (randAmt % initialMint) / 100 + 1; // with seqLen: 100 we should not have supply issues
        uint poolId = randPool % totalNbPools;
        ERC20 poolToken = ERC20(reliquary.getPoolInfo(poolId).poolToken);
        uint balanceReliquaryBefore = poolToken.balanceOf(address(reliquary));
        uint balanceUserBefore = poolToken.balanceOf(address(user));

        // if the user already has a relic, use deposit()
        (bool success, bytes memory data) = user.proxy(
            address(reliquary),
            abi.encodeWithSelector(
                reliquary.createRelicAndDeposit.selector,
                address(user),
                poolId,
                amount
            )
        );
        assert(success);
        uint relicId = abi.decode(data, (uint));
        isInit[relicId] = true;
        relicIds.push(relicId);

        // reliquary balance must have increased by amount
        assert(poolToken.balanceOf(address(reliquary)) == balanceReliquaryBefore + amount);
        // user balance must have decreased by amount
        assert(poolToken.balanceOf(address(user)) == balanceUserBefore - amount);
    }

    /// random user deposit
    function randDeposit(uint randRelic, uint randAmt) public {
        uint relicId = relicIds[randRelic % relicIds.length];
        User user = User(reliquary.ownerOf(relicId));
        uint amount = (randAmt % initialMint) / 100 + 1; // with seqLen: 100 we should not have supply issues
        ERC20 poolToken = ERC20(reliquary.getPoolInfo(reliquary.getPositionForId(relicId).poolId).poolToken);
        uint balanceReliquaryBefore = poolToken.balanceOf(address(reliquary));
        uint balanceUserBefore = poolToken.balanceOf(address(user));

        // if the user already has a relic, use deposit()
        if (isInit[relicId]) {
            (bool success, ) = user.proxy(
                address(reliquary),
                abi.encodeWithSelector(reliquary.deposit.selector, amount, relicId)
            );
            assert(success);
        }

        // reliquary balance must have increased by amount
        assert(poolToken.balanceOf(address(reliquary)) == balanceReliquaryBefore + amount);
        // user balance must have decreased by amount
        assert(poolToken.balanceOf(address(user)) == balanceUserBefore - amount);
    }

    /// random withdraw
    function randWithdraw(uint randRelic, uint randAmt) public {
        uint relicId = relicIds[randRelic % relicIds.length];
        User user = User(reliquary.ownerOf(relicId));
        uint amount = reliquary.getPositionForId(relicId).amount;

        if (amount > 0) {
            uint amountToWithdraw = randAmt % (amount + 1);
            require(amountToWithdraw > 0);

            uint poolId = reliquary.getPositionForId(relicId).poolId;
            ERC20 poolToken = ERC20(reliquary.getPoolInfo(poolId).poolToken);

            uint balanceReliquaryBefore = poolToken.balanceOf(address(reliquary));
            uint balanceUserBefore = poolToken.balanceOf(address(user));

            // if the user already have a relic use deposit()
            (bool success, ) = user.proxy(
                address(reliquary),
                abi.encodeWithSelector(
                    reliquary.withdraw.selector,
                    amountToWithdraw, // withdraw more than amount deposited ]0, amount]
                    relicId
                )
            );
            assert(success);

            // reliquary balance must have decreased by amountToWithdraw
            assert(
                poolToken.balanceOf(address(reliquary)) == balanceReliquaryBefore - amountToWithdraw
            );
            // user balance must have increased by amountToWithdraw
            assert(poolToken.balanceOf(address(user)) == balanceUserBefore + amountToWithdraw);
        }
    }

    /// random withdraw + harvest
    function randWithdrawAndHarvest(uint randRelic, uint randAmt) public {
        uint relicId = relicIds[randRelic % relicIds.length];
        User user = User(reliquary.ownerOf(relicId));
        uint amount = reliquary.getPositionForId(relicId).amount;

        if (amount > 0) {
            uint amountToWithdraw = randAmt % (amount + 1);

            uint poolId = reliquary.getPositionForId(relicId).poolId;
            ERC20 poolToken = ERC20(reliquary.getPoolInfo(poolId).poolToken);

            uint balanceReliquaryBefore = poolToken.balanceOf(address(reliquary));
            uint balanceUserBefore = poolToken.balanceOf(address(user));

            // if the user already have a relic use deposit()
            (bool success, ) = user.proxy(
                address(reliquary),
                abi.encodeWithSelector(
                    reliquary.withdrawAndHarvest.selector,
                    amountToWithdraw, // withdraw more than amount deposited ]0, amount]
                    relicId,
                    address(user)
                )
            );
            require(success);

            // reliquary balance must have decreased by amountToWithdraw
            assert(
                poolToken.balanceOf(address(reliquary)) == balanceReliquaryBefore - amountToWithdraw
            );
            // user balance must have increased by amountToWithdraw
            assert(poolToken.balanceOf(address(user)) == balanceUserBefore + amountToWithdraw);
        }
    }

    /// random emergency withdraw
    function randEmergencyWithdraw(uint rand) public {
        uint relicId = relicIds[rand % relicIds.length];

        PositionInfo memory pi = reliquary.getPositionForId(relicId);
        address owner = reliquary.ownerOf(relicId);
        ERC20 poolToken = ERC20(reliquary.getPoolInfo(pi.poolId).poolToken);
        uint amount = pi.amount;

        uint balanceReliquaryBefore = poolToken.balanceOf(address(reliquary));
        uint balanceOwnerBefore = poolToken.balanceOf(owner);

        rewardLostByEmergencyWithdraw += reliquary.pendingReward(relicId);

        (bool success, ) = User(owner).proxy(
            address(reliquary),
            abi.encodeWithSelector(reliquary.emergencyWithdraw.selector, relicId)
        );
        require(success);

        isInit[relicId] = false;

        // reliquary balance must have decreased by amount
        assert(poolToken.balanceOf(address(reliquary)) == balanceReliquaryBefore - amount);
        // user balance must have increased by amount
        assert(poolToken.balanceOf(address(owner)) == balanceOwnerBefore + amount);
    }

    /// harvest a position randomly
    function randHarvestPosition(uint rand) public {
        uint idToHasvest = rand % relicIds.length;
        address owner = reliquary.ownerOf(idToHasvest);

        uint balanceReliquaryBefore = rewardToken.balanceOf(address(reliquary));
        uint balanceOwnerBefore = rewardToken.balanceOf(owner);
        uint amount = reliquary.pendingReward(idToHasvest);

        (bool success, ) = User(owner).proxy(
            address(reliquary),
            abi.encodeWithSelector(reliquary.harvest.selector, idToHasvest, owner)
        );
        require(success);

        // reliquary balance must have increased by amount
        assert(rewardToken.balanceOf(address(reliquary)) == balanceReliquaryBefore - amount);
        // user balance must have decreased by amount
        assert(rewardToken.balanceOf(address(owner)) == balanceOwnerBefore + amount);
    }

    /// random split
    function randSplit(uint randRelic, uint randAmt, uint randUserTo) public {
        uint relicIdFrom = relicIds[randRelic % relicIds.length];
        PositionInfo memory piFrom = reliquary.getPositionForId(relicIdFrom);
        uint amount = (randAmt % piFrom.amount);
        User owner = User(reliquary.ownerOf(relicIdFrom));
        User to = User(users[randUserTo % users.length]);

        uint amountFromBefore = piFrom.amount;

        (bool success, bytes memory data) = owner.proxy(
            address(reliquary),
            abi.encodeWithSelector(reliquary.split.selector, relicIdFrom, amount, address(to))
        );
        require(success);
        uint relicIdTo = abi.decode(data, (uint));
        isInit[relicIdTo] = true;
        relicIds.push(relicIdTo);

        assert(reliquary.getPositionForId(relicIdFrom).amount == amountFromBefore - amount);
        assert(reliquary.getPositionForId(relicIdTo).amount == amount);
    }

    /// random shift
    function randShift(uint randRelicFrom, uint randRelicTo, uint randAmt) public {
        uint relicIdFrom = relicIds[randRelicFrom % relicIds.length];
        User user = User(reliquary.ownerOf(relicIdFrom)); // same user for from and to
        require(reliquary.balanceOf(address(user)) >= 2);
        uint relicIdTo = relicIds[randRelicTo % relicIds.length];
        require(reliquary.ownerOf(relicIdTo) == address(user));

        uint amountFromBefore = reliquary.getPositionForId(relicIdFrom).amount;
        uint amountToBefore = reliquary.getPositionForId(relicIdTo).amount;
        uint amount = (randAmt % amountFromBefore);

        (bool success, ) = user.proxy(
            address(reliquary),
            abi.encodeWithSelector(reliquary.shift.selector, relicIdFrom, relicIdTo, amount)
        );
        require(success);

        assert(reliquary.getPositionForId(relicIdFrom).amount == amountFromBefore - amount);
        assert(reliquary.getPositionForId(relicIdTo).amount == amountToBefore + amount);
    }

    /// random merge
    function randMerge(uint randRelicFrom, uint randRelicTo) public {
        uint relicIdFrom = relicIds[randRelicFrom % relicIds.length];
        User user = User(reliquary.ownerOf(relicIdFrom)); // same user for from and to
        require(reliquary.balanceOf(address(user)) >= 2);
        uint relicIdTo = relicIds[randRelicTo % relicIds.length];
        // require(reliquary.ownerOf(relicIdTo) == address(user));

        uint amountFromBefore = reliquary.getPositionForId(relicIdFrom).amount;
        uint amountToBefore = reliquary.getPositionForId(relicIdTo).amount;
        uint amount = amountFromBefore;

        (bool success, ) = user.proxy(
            address(reliquary),
            abi.encodeWithSelector(reliquary.merge.selector, relicIdFrom, relicIdTo)
        );
        require(success);

        isInit[relicIdFrom] = false;

        assert(reliquary.getPositionForId(relicIdFrom).amount == 0);
        assert(reliquary.getPositionForId(relicIdTo).amount == amountToBefore + amount);
    }

    /// update a position randomly
    function randUpdatePosition(uint rand) public {
        reliquary.updatePosition(rand % relicIds.length);
    }

    /// update a pool randomly
    function randUpdatePools(uint rand) public {
        reliquary.updatePool(rand % totalNbPools);
    }

    /// random burn
    function randBurn(uint rand) public {
        uint idToBurn = relicIds[rand % relicIds.length];

        try reliquary.burn(idToBurn) {
            assert(isInit[idToBurn]);
            isInit[idToBurn] = false;
        } catch {
            assert(true);
        }
    }

    // ---------------------- Invariants ----------------------

    /// @custom:invariant - A user should never be able to withdraw more than deposited.
    function tryTowithdrawMoreThanDeposit(uint randRelic, uint randAmt) public {
        uint relicId = relicIds[randRelic % relicIds.length];
        User user = User(reliquary.ownerOf(relicId));
        uint amount = reliquary.getPositionForId(relicId).amount;

        require(randAmt > amount);

        // if the user already have a relic use deposit()
        (bool success, ) = user.proxy(
            address(reliquary),
            abi.encodeWithSelector(
                reliquary.withdraw.selector,
                randAmt, // withdraw more than amount deposited ]amount, uint256.max]
                relicId
            )
        );
        assert(!success);
    }

    /// @custom:invariant - No `position.entry` should be greater than `block.timestamp`.
    /// @custom:invariant - The sum of all `position.amount` should never be greater than total deposit.
    function positionParamsIntegrity() public view {
        uint[] memory totalAmtInPositions;
        PositionInfo memory pi;
        for (uint i; i < relicIds.length; i++) {
            pi = reliquary.getPositionForId(relicIds[i]);
            assert(pi.entry <= block.timestamp);
            totalAmtInPositions[pi.poolId] += pi.amount;
        }

        // this works if there are no pools with twice the same token
        for (uint pid; pid < totalNbPools; pid++) {
            uint totalBalance = ERC20(reliquary.getPoolInfo(pid).poolToken).balanceOf(address(reliquary));
            // check balances integrity
            assert(totalAmtInPositions[pid] == totalBalance);
        }
    }

    /// @custom:invariant - The sum of all `allocPoint` should be equal to `totalAllocpoint`.
    function poolallocPointIntegrity() public view {
        uint sum;
        for (uint i = 0; i < poolIds.length; i++) {
            sum += reliquary.getPoolInfo(i).allocPoint;
        }
        assert(sum == reliquary.totalAllocPoint());
    }

    /// @custom:invariant - The total reward harvested and pending should never be greater than the total emission rate.
    /// @custom:invariant - `emergencyWithdraw` should burn position rewards.
    function poolEmissionIntegrity() public {
        // require(block.timestamp > startTimestamp + 12);
        uint totalReward = rewardLostByEmergencyWithdraw;

        for (uint i = 0; i < totalNbUsers; i++) {
            // account for tokenReward harvested
            totalReward += rewardToken.balanceOf(address(users[i]));
        }

        for (uint i = 0; i < relicIds.length; i++) {
            uint relicId = relicIds[i];
            // account for tokenReward pending
            // check if position was burned
            if (isInit[relicId]) {
                totalReward += reliquary.pendingReward(relicId);
            }
        }

        // only works for constant emission rate
        uint maxEmission = (block.timestamp - startTimestamp) * reliquary.emissionRate();

        emit LogUint(totalReward);
        emit LogUint(maxEmission);

        assert(totalReward <= maxEmission);
    }

    // ---------------------- Helpers ----------------------
}
