// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "contracts/Reliquary.sol";
import "contracts/interfaces/IReliquary.sol";
import "contracts/interfaces/IVoter.sol";
import "contracts/interfaces/IPool.sol";
import "contracts/nft_descriptors/NFTDescriptor.sol";
import "contracts/curves/LinearCurve.sol";
import "contracts/curves/LinearPlateauCurve.sol";
import "openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "contracts/curves/PolynomialPlateauCurve.sol";
import "./mocks/ERC20Mock.sol";
import "./mocks/VoterMock.sol";

contract GaugeRewardsTest is ERC721Holder, Test {
    using Strings for address;
    using Strings for uint256;

    Reliquary reliquary;
    LinearCurve linearCurve;
    LinearPlateauCurve linearPlateauCurve;
    PolynomialPlateauCurve polynomialPlateauCurve;
    ERC20Mock oath;
    IERC20Metadata poolToken;
    address nftDescriptor;
    IVoter voter;
    address gaugeReceiver;
    uint256 emissionRate = 1e17;

    IERC20Metadata lpToken0;
    IERC20Metadata lpToken1;
    IERC20Metadata rewardToken;

    // Linear function config (to config)
    uint256 slope = 100; // Increase of multiplier every second
    uint256 minMultiplier = 365 days * 100; // Arbitrary (but should be coherent with slope)
    uint256 plateau = 10 days;
    int256[] public coeff = [int256(100e18), int256(1e18), int256(5e15), int256(-1e13), int256(5e9)];

    function setUp() public {
        vm.createSelectFork("mode");
        
        lpToken0 = IERC20Metadata(0x4200000000000000000000000000000000000006); // weth
        lpToken1 = IERC20Metadata(0xd988097fb8612cc24eeC14542bC03424c656005f); // usdc

        voter = IVoter(0xD2F998a46e4d9Dd57aF1a28EBa8C34E7dD3851D7);
        vm.label(address(voter), "Voter");
        rewardToken = IERC20Metadata(0xDfc7C877a950e49D2610114102175A06C2e3167a);
        vm.label(address(rewardToken), "Reward Token");

        hoax(address(this));

        int256[] memory coeffDynamic = new int256[](5);
        for (uint256 i = 0; i < 5; i++) {
            coeffDynamic[i] = coeff[i];
        }

        oath = new ERC20Mock(18);
        gaugeReceiver = makeAddr("gaugeReceiver");
        reliquary = new Reliquary(address(oath), emissionRate, gaugeReceiver, address(voter), "Reliquary Deposit", "RELIC");
        linearPlateauCurve = new LinearPlateauCurve(slope, minMultiplier, plateau);
        linearCurve = new LinearCurve(slope, minMultiplier);
        polynomialPlateauCurve = new PolynomialPlateauCurve(coeffDynamic, 850);

        oath.mint(address(reliquary), 100_000_000 ether);

        poolToken = IERC20Metadata(0xCc16Bfda354353B2E03214d2715F514706Be044C);
        nftDescriptor = address(new NFTDescriptor(address(reliquary)));

        // poolToken.mint(address(this), 100_000_000 ether);
        deal(address(lpToken0), address(this), 100_000 ether);
        deal(address(lpToken1), address(this), 100_000 ether);

        lpToken0.transfer(address(poolToken), 100_000 ether);
        lpToken1.transfer(address(poolToken), 100_000 ether);
        IPool(address(poolToken)).mint(address(this));

        uint256 balance = IERC20Metadata(address(poolToken)).balanceOf(address(this));
        IERC20Metadata(address(poolToken)).approve(address(reliquary), type(uint256).max);
        console.log("Pool Token Balance: %e", balance);
        
        reliquary.grantRole(keccak256("OPERATOR"), address(this));
        reliquary.addPool(
            100,
            address(poolToken),
            address(0),
            linearCurve,
            "ETH Pool",
            nftDescriptor,
            true,
            address(5)
        );
    }

    function testPolynomialCurve() public view {
        console.log(polynomialPlateauCurve.getFunction(8500));
    }

    function testModifyPool() public {
        vm.expectEmit(true, true, false, true);
        emit ReliquaryEvents.LogPoolModified(0, 100, address(0), nftDescriptor);
        reliquary.modifyPool(0, 100, address(0), "USDC Pool", nftDescriptor, true);
    }

    function testRevertOnModifyInvalidPool() public {
        vm.expectRevert(IReliquary.Reliquary__NON_EXISTENT_POOL.selector);
        reliquary.modifyPool(1, 100, address(0), "USDC Pool", nftDescriptor, true);
    }

    function testRevertOnModifyPoolUnauthorized() public {
        vm.expectRevert();
        vm.prank(address(1));
        reliquary.modifyPool(0, 100, address(0), "USDC Pool", nftDescriptor, true);
    }

    function testPendingOath(uint256 amount, uint256 time) public {
        time = bound(time, 0, 3650 days);
        amount = bound(amount, 1, poolToken.balanceOf(address(this)));
        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, amount);
        skip(time);
        reliquary.update(relicId, address(0));
        // reliquary.pendingReward(1) is the bootstrapped relic.
        assertApproxEqAbs(
            reliquary.pendingReward(relicId) + reliquary.pendingReward(1),
            time * emissionRate,
            (time * emissionRate) / 100000
        ); // max 0,0001%
    }

    // function testMassUpdatePools() public {
    //     skip(1);
    //     uint256[] memory pools = new uint256[](1);
    //     pools[0] = 0;
    //     vm.expectEmit(true, false, false, true);
    //     emit ReliquaryEvents.LogUpdatePool(0, block.timestamp, 0, 0);
    //     reliquary.massUpdatePools();
    // }

    function testCreateRelicAndDeposit(uint256 amount) public {
        amount = bound(amount, 1, poolToken.balanceOf(address(this)));
        vm.expectEmit(true, true, true, true);
        emit ReliquaryEvents.Deposit(0, amount, address(this), 2);
        reliquary.createRelicAndDeposit(address(this), 0, amount);
    }

    function testDepositExisting(uint256 amountA, uint256 amountB) public {
        amountA = bound(amountA, 1, type(uint256).max / 2);
        amountB = bound(amountB, 1, type(uint256).max / 2);
        vm.assume(amountA + amountB <= poolToken.balanceOf(address(this)));
        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, amountA);
        reliquary.deposit(amountB, relicId, address(0));
        assertEq(reliquary.getPositionForId(relicId).amount, amountA + amountB);
    }

    function testRevertOnDepositInvalidPool(uint8 pool) public {
        pool = uint8(bound(pool, 1, type(uint8).max));
        vm.expectRevert(IReliquary.Reliquary__NON_EXISTENT_POOL.selector);
        reliquary.createRelicAndDeposit(address(this), pool, 1);
    }

    function testRevertOnDepositUnauthorized() public {
        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, 1);
        vm.expectRevert(IReliquary.Reliquary__NOT_APPROVED_OR_OWNER.selector);
        vm.prank(address(1));
        reliquary.deposit(1, relicId, address(0));
    }

    function testWithdraw(uint256 amount) public {
        amount = bound(amount, 1, poolToken.balanceOf(address(this)));
        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, amount);
        vm.expectEmit(true, true, true, true);
        emit ReliquaryEvents.Withdraw(0, amount, address(this), relicId);
        reliquary.withdraw(amount, relicId, address(0));
    }

    function testRevertOnWithdrawUnauthorized() public {
        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, 1);
        vm.expectRevert(IReliquary.Reliquary__NOT_APPROVED_OR_OWNER.selector);
        vm.prank(address(1));
        reliquary.withdraw(1, relicId, address(0));
    }

    function testHarvest(uint256 amount0, uint256 amount1) public {
        amount0 = bound(amount0, 1 ether, poolToken.balanceOf(address(this)));
        amount1 = bound(amount1, 1 ether, poolToken.balanceOf(address(this)));
        vm.assume((amount0 + amount1) <= poolToken.balanceOf(address(this)));

        poolToken.transfer(address(1), amount0);

        vm.startPrank(address(1));
        poolToken.approve(address(reliquary), type(uint256).max);
        uint256 relicIdA = reliquary.createRelicAndDeposit(address(1), 0, amount0 / 2);
        skip(180 days);

        reliquary.withdraw((7500 * amount0 / 2) / 10_000, relicIdA, address(0));
        reliquary.deposit(amount0 / 2, relicIdA, address(0));

        
        vm.stopPrank();
        uint256 relicIdB = reliquary.createRelicAndDeposit(address(this), 0, amount1);
        skip(180 days);

        /* update reward credit only */
        reliquary.update(relicIdB, address(0));
        PositionInfo memory initPositionB = reliquary.getPositionForId(relicIdB);
        /* harvest */
        reliquary.update(relicIdB, address(this));
        PositionInfo memory finalPositionB = reliquary.getPositionForId(relicIdB);

        vm.startPrank(address(1));
        reliquary.update(relicIdA, address(0));
        
        /* update reward credit only */
        PositionInfo memory initPositionA = reliquary.getPositionForId(relicIdA);
        reliquary.update(relicIdA, address(this));
        /* harvest */
        PositionInfo memory finalPositionA = reliquary.getPositionForId(relicIdA);
        vm.stopPrank();

        uint256 deltaA = initPositionA.rewardCredit - finalPositionA.rewardCredit ;
        uint256 deltaB = initPositionB.rewardCredit - finalPositionB.rewardCredit ;

        assertApproxEqAbs(oath.balanceOf(address(this)), deltaA + deltaB, 1);
    }

    function testRevertOnHarvestUnauthorized() public {
        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, 1);
        vm.expectRevert(IReliquary.Reliquary__NOT_APPROVED_OR_OWNER.selector);
        vm.prank(address(1));
        reliquary.update(relicId, address(this));
    }

    function testEmergencyWithdraw(uint256 amount) public {
        amount = bound(amount, 1, poolToken.balanceOf(address(this)));
        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, amount);
        vm.expectEmit(true, true, true, true);
        emit ReliquaryEvents.EmergencyWithdraw(0, amount, address(this), relicId);
        reliquary.emergencyWithdraw(relicId);
    }

    function testRevertOnEmergencyWithdrawNotOwner() public {
        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, 1);
        vm.expectRevert(IReliquary.Reliquary__NOT_OWNER.selector);
        vm.prank(address(1));
        reliquary.emergencyWithdraw(relicId);
    }

    function testSplit(uint256 depositAmount, uint256 splitAmount) public {
        depositAmount = bound(depositAmount, 1, poolToken.balanceOf(address(this)));
        splitAmount = bound(splitAmount, 1, depositAmount);

        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount);
        uint256 newRelicId = reliquary.split(relicId, splitAmount, address(this));

        assertEq(reliquary.balanceOf(address(this)), 2);
        assertEq(reliquary.getPositionForId(relicId).amount, depositAmount - splitAmount);
        assertEq(reliquary.getPositionForId(newRelicId).amount, splitAmount);
    }

    function testRevertOnSplitUnderflow(uint256 depositAmount, uint256 splitAmount) public {
        depositAmount = bound(depositAmount, 1, poolToken.balanceOf(address(this)) / 2 - 1);
        splitAmount = bound(
            splitAmount, depositAmount + 1, poolToken.balanceOf(address(this)) - depositAmount
        );

        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount);
        vm.expectRevert(stdError.arithmeticError);
        reliquary.split(relicId, splitAmount, address(this));
    }

    function testShift(uint256 depositAmount1, uint256 depositAmount2, uint256 shiftAmount)
        public
    {
        depositAmount1 = bound(depositAmount1, 1, poolToken.balanceOf(address(this)) - 1);
        depositAmount2 =
            bound(depositAmount2, 1, poolToken.balanceOf(address(this)) - depositAmount1);
        shiftAmount = bound(shiftAmount, 1, depositAmount1);

        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount1);
        uint256 newRelicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount2);
        reliquary.shift(relicId, newRelicId, shiftAmount);

        assertEq(reliquary.getPositionForId(relicId).amount, depositAmount1 - shiftAmount);
        assertEq(reliquary.getPositionForId(newRelicId).amount, depositAmount2 + shiftAmount);
    }

    function testRevertOnShiftUnderflow(uint256 depositAmount, uint256 shiftAmount) public {
        depositAmount = bound(depositAmount, 1, poolToken.balanceOf(address(this)) / 2 - 1);
        shiftAmount = bound(
            shiftAmount, depositAmount + 1, poolToken.balanceOf(address(this)) - depositAmount
        );

        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount);
        uint256 newRelicId = reliquary.createRelicAndDeposit(address(this), 0, 1);
        vm.expectRevert(stdError.arithmeticError);
        reliquary.shift(relicId, newRelicId, shiftAmount);
    }

    function testMerge(uint256 depositAmount1, uint256 depositAmount2) public {
        depositAmount1 = bound(depositAmount1, 1, poolToken.balanceOf(address(this)) - 1);
        depositAmount2 =
            bound(depositAmount2, 1, poolToken.balanceOf(address(this)) - depositAmount1);

        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount1);
        uint256 newRelicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount2);
        reliquary.merge(relicId, newRelicId);

        assertEq(reliquary.getPositionForId(newRelicId).amount, depositAmount1 + depositAmount2);
    }

    function testCompareDepositAndMerge(uint256 amount1, uint256 amount2, uint256 time) public {
        amount1 = bound(amount1, 1, poolToken.balanceOf(address(this)) - 1);
        amount2 = bound(amount2, 1, poolToken.balanceOf(address(this)) - amount1);
        time = bound(time, 1, 356 days * 1); // 100 years

        console.log(amount1);
        console.log(amount2);
        console.log(time);

        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, amount1);
        skip(time);
        reliquary.deposit(amount2, relicId, address(0));
        uint256 maturity1 = block.timestamp - reliquary.getPositionForId(relicId).entry;

        //reset maturity
        reliquary.withdraw(amount1 + amount2, relicId, address(0));
        reliquary.deposit(amount1, relicId, address(0));

        skip(time);
        uint256 newRelicId = reliquary.createRelicAndDeposit(address(this), 0, amount2);
        reliquary.merge(newRelicId, relicId);
        uint256 maturity2 = block.timestamp - reliquary.getPositionForId(relicId).entry;

        assertApproxEqAbs(maturity1, maturity2, 1);
    }

    function testMergeAfterSplit(uint256 amount0, uint256 amount1, uint256 amountToSplit) public {
        amount0 = bound(amount0, 1 ether, poolToken.balanceOf(address(this)));
        amount1 = bound(amount1, 1 ether, poolToken.balanceOf(address(this)));
        amountToSplit = bound(amountToSplit, 1 ether, amount0);
        vm.assume((amount0 + amount1) <= poolToken.balanceOf(address(this)));
        

        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, amount0);
        skip(2 days);
        reliquary.update(relicId, address(this));
        reliquary.split(relicId, amountToSplit, address(this));
        uint256 newRelicId = reliquary.createRelicAndDeposit(address(this), 0, amount1);
        reliquary.merge(relicId, newRelicId);
        assertApproxEqAbs(reliquary.getPositionForId(newRelicId).amount, (amount0 - amountToSplit) + amount1, 1);
    }

    function testBurn() public {
        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, 1 ether);
        vm.expectRevert(IReliquary.Reliquary__BURNING_PRINCIPAL.selector);
        reliquary.burn(relicId);

        reliquary.withdraw(1 ether, relicId, address(this));
        vm.expectRevert(IReliquary.Reliquary__NOT_APPROVED_OR_OWNER.selector);
        vm.prank(address(1));
        reliquary.burn(relicId);
        assertEq(reliquary.balanceOf(address(this)), 1);

        reliquary.burn(relicId);
        assertEq(reliquary.balanceOf(address(this)), 0);
    }

    function testPocShiftVulnerability(uint256 amount) public {
        amount = bound(amount, 1 ether, poolToken.balanceOf(address(this)));
        
        uint256 idParent = reliquary.createRelicAndDeposit(address(this), 0, amount/2);
        skip(366 days);
        reliquary.update(idParent, address(0));

        for (uint256 i = 0; i < 10; i++) {
            uint256 idChild = reliquary.createRelicAndDeposit(address(this), 0, amount/2000);
            reliquary.shift(idParent, idChild, 1);
            reliquary.update(idParent, address(0));
            uint256 levelChild = reliquary.getPositionForId(idChild).level;
            assertEq(levelChild, 0); // assert max level
        }
    }

    function testGaugeReward() public {
        uint256 amount = 1 ether;
        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, amount);
        skip(1 days);
        reliquary.update(relicId, address(this));
        reliquary.claimGaugeRewards(0);
        console.log("reward: ", rewardToken.balanceOf(gaugeReceiver));
    }

    // function testDepositBonusRewarder() public {
    //     DepositBonusRewarder rewarder = new DepositBonusRewarder(
    //         1000 ether,
    //         1 ether,
    //         1 days,
    //         address(oath),
    //         address(reliquary)
    //     );
    //     oath.mint(address(rewarder), 1_000_000 ether);

    //     reliquary.addPool(
    //         100,
    //         address(poolToken),
    //         address(rewarder),
    //         linearPlateauCurve,
    //         "ETH Pool",
    //         nftDescriptor,
    //         true
    //     );

    //     uint relicId = reliquary.createRelicAndDeposit(address(this), 1, 1 ether);
    //     skip(1 days);
    //     rewarder.claimDepositBonus(relicId, address(this));

    //     assertEq(oath.balanceOf(address(this)), 1000 ether);
    // }

    // function testParentRewarder() public {
    //     ERC20Mock parentToken = new ERC20Mock("Parent Token", "PT", 18);
    //     ParentRewarder parent = new ParentRewarder(5e17, address(parentToken), address(reliquary));
    //     parentToken.mint(address(parent), 1_000_000 ether);
    //     parent.grantRole(keccak256("CHILD_SETTER"), address(this));

    //     ERC20Mock childToken = new ERC20Mock("Child Token", "CT", 6);
    //     address child = parent.createChild(address(childToken), 2e6, address(this));
    //     childToken.mint(child, 1_000_000 ether);

    //     reliquary.addPool(
    //         100,
    //         address(poolToken),
    //         address(parent),
    //         linearPlateauCurve,
    //         "ETH Pool",
    //         nftDescriptor,
    //         true
    //     );

    //     uint relicId = reliquary.createRelicAndDeposit(address(this), 1, 1 ether);
    //     skip(1 days);
    //     reliquary.update(relicId, address(this));

    //     assertApproxEqAbs(oath.balanceOf(address(this)), 4320 ether, 1e15);
    //     assertApproxEqAbs(parentToken.balanceOf(address(this)), 2160 ether, 1e15);
    //     assertApproxEqAbs(childToken.balanceOf(address(this)), 8640e6, 1e15);
    // }
}
