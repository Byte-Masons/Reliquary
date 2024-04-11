// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "contracts/Reliquary.sol";
import "contracts/interfaces/IReliquary.sol";
import "contracts/nft_descriptors/NFTDescriptor.sol";
import "contracts/curves/LinearCurve.sol";
import "contracts/curves/LinearPlateauCurve.sol";
import "openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";
import "contracts/curves/PolynomialPlateauCurve.sol";
import "./mocks/ERC20Mock.sol";

contract ReliquaryTest is ERC721Holder, Test {
    using Strings for address;
    using Strings for uint256;

    Reliquary reliquary;
    LinearCurve linearCurve;
    LinearPlateauCurve linearPlateauCurve;
    PolynomialPlateauCurve polynomialPlateauCurve;
    ERC20Mock oath;
    ERC20Mock testToken;
    address nftDescriptor;
    uint256 emissionRate = 1e17;

    // Linear function config (to config)
    uint256 slope = 100; // Increase of multiplier every second
    uint256 minMultiplier = 365 days * 100; // Arbitrary (but should be coherent with slope)
    uint256 plateau = 10 days;
    int256[] public coeff = [int256(100e18), int256(1e18), int256(5e15), int256(-1e13), int256(5e9)];

    function setUp() public {
        int256[] memory coeffDynamic = new int256[](5);
        for (uint256 i = 0; i < 5; i++) {
            coeffDynamic[i] = coeff[i];
        }

        oath = new ERC20Mock(18);
        reliquary = new Reliquary(address(oath), emissionRate, "Reliquary Deposit", "RELIC");
        linearPlateauCurve = new LinearPlateauCurve(slope, minMultiplier, plateau);
        linearCurve = new LinearCurve(slope, minMultiplier);
        polynomialPlateauCurve = new PolynomialPlateauCurve(coeffDynamic, 850);

        oath.mint(address(reliquary), 100_000_000 ether);

        testToken = new ERC20Mock(6);
        nftDescriptor = address(new NFTDescriptor(address(reliquary)));

        reliquary.grantRole(keccak256("OPERATOR"), address(this));
        reliquary.addPool(
            100, address(testToken), address(0), linearCurve, "ETH Pool", nftDescriptor, true
        );

        testToken.mint(address(this), 100_000_000 ether);
        testToken.approve(address(reliquary), type(uint256).max);
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
        amount = bound(amount, 1, testToken.balanceOf(address(this)));
        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, amount);
        skip(time);
        reliquary.update(relicId, address(0));
        assertApproxEqAbs(
            reliquary.pendingReward(relicId), time * emissionRate, (time * emissionRate) / 100000
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
        amount = bound(amount, 1, testToken.balanceOf(address(this)));
        vm.expectEmit(true, true, true, true);
        emit ReliquaryEvents.Deposit(0, amount, address(this), 1);
        reliquary.createRelicAndDeposit(address(this), 0, amount);
    }

    function testDepositExisting(uint256 amountA, uint256 amountB) public {
        amountA = bound(amountA, 1, type(uint256).max / 2);
        amountB = bound(amountB, 1, type(uint256).max / 2);
        vm.assume(amountA + amountB <= testToken.balanceOf(address(this)));
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
        amount = bound(amount, 1, testToken.balanceOf(address(this)));
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

    function testHarvest() public {
        testToken.transfer(address(1), 1.25 ether);

        vm.startPrank(address(1));
        testToken.approve(address(reliquary), type(uint256).max);
        uint256 relicIdA = reliquary.createRelicAndDeposit(address(1), 0, 1 ether);
        skip(180 days);
        reliquary.withdraw(0.75 ether, relicIdA, address(0));
        reliquary.deposit(1 ether, relicIdA, address(0));

        vm.stopPrank();
        uint256 relicIdB = reliquary.createRelicAndDeposit(address(this), 0, 100 ether);
        skip(180 days);
        reliquary.update(relicIdB, address(this));

        vm.startPrank(address(1));
        reliquary.update(relicIdA, address(this));
        vm.stopPrank();

        assertApproxEqAbs(oath.balanceOf(address(this)) / 1e18, 3110400, 1);
    }

    function testRevertOnHarvestUnauthorized() public {
        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, 1);
        vm.expectRevert(IReliquary.Reliquary__NOT_APPROVED_OR_OWNER.selector);
        vm.prank(address(1));
        reliquary.update(relicId, address(this));
    }

    function testEmergencyWithdraw(uint256 amount) public {
        amount = bound(amount, 1, testToken.balanceOf(address(this)));
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
        depositAmount = bound(depositAmount, 1, testToken.balanceOf(address(this)));
        splitAmount = bound(splitAmount, 1, depositAmount);

        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount);
        uint256 newRelicId = reliquary.split(relicId, splitAmount, address(this));

        assertEq(reliquary.balanceOf(address(this)), 2);
        assertEq(reliquary.getPositionForId(relicId).amount, depositAmount - splitAmount);
        assertEq(reliquary.getPositionForId(newRelicId).amount, splitAmount);
    }

    function testRevertOnSplitUnderflow(uint256 depositAmount, uint256 splitAmount) public {
        depositAmount = bound(depositAmount, 1, testToken.balanceOf(address(this)) / 2 - 1);
        splitAmount = bound(
            splitAmount, depositAmount + 1, testToken.balanceOf(address(this)) - depositAmount
        );

        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount);
        vm.expectRevert(stdError.arithmeticError);
        reliquary.split(relicId, splitAmount, address(this));
    }

    function testShift(uint256 depositAmount1, uint256 depositAmount2, uint256 shiftAmount)
        public
    {
        depositAmount1 = bound(depositAmount1, 1, testToken.balanceOf(address(this)) - 1);
        depositAmount2 =
            bound(depositAmount2, 1, testToken.balanceOf(address(this)) - depositAmount1);
        shiftAmount = bound(shiftAmount, 1, depositAmount1);

        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount1);
        uint256 newRelicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount2);
        reliquary.shift(relicId, newRelicId, shiftAmount);

        assertEq(reliquary.getPositionForId(relicId).amount, depositAmount1 - shiftAmount);
        assertEq(reliquary.getPositionForId(newRelicId).amount, depositAmount2 + shiftAmount);
    }

    function testRevertOnShiftUnderflow(uint256 depositAmount, uint256 shiftAmount) public {
        depositAmount = bound(depositAmount, 1, testToken.balanceOf(address(this)) / 2 - 1);
        shiftAmount = bound(
            shiftAmount, depositAmount + 1, testToken.balanceOf(address(this)) - depositAmount
        );

        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount);
        uint256 newRelicId = reliquary.createRelicAndDeposit(address(this), 0, 1);
        vm.expectRevert(stdError.arithmeticError);
        reliquary.shift(relicId, newRelicId, shiftAmount);
    }

    function testMerge(uint256 depositAmount1, uint256 depositAmount2) public {
        depositAmount1 = bound(depositAmount1, 1, testToken.balanceOf(address(this)) - 1);
        depositAmount2 =
            bound(depositAmount2, 1, testToken.balanceOf(address(this)) - depositAmount1);

        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount1);
        uint256 newRelicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount2);
        reliquary.merge(relicId, newRelicId);

        assertEq(reliquary.getPositionForId(newRelicId).amount, depositAmount1 + depositAmount2);
    }

    function testCompareDepositAndMerge(uint256 amount1, uint256 amount2, uint256 time) public {
        amount1 = bound(amount1, 1, testToken.balanceOf(address(this)) - 1);
        amount2 = bound(amount2, 1, testToken.balanceOf(address(this)) - amount1);
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

    function testMergeAfterSplit() public {
        uint256 depositAmount1 = 100 ether;
        uint256 depositAmount2 = 50 ether;
        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount1);
        skip(2 days);
        reliquary.update(relicId, address(this));
        reliquary.split(relicId, 50 ether, address(this));
        uint256 newRelicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount2);
        reliquary.merge(relicId, newRelicId);
        assertEq(reliquary.getPositionForId(newRelicId).amount, 100 ether);
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

    function testPocShiftVulnerability() public {
        uint256 idParent = reliquary.createRelicAndDeposit(address(this), 0, 10000 ether);
        skip(366 days);
        reliquary.update(idParent, address(0));

        for (uint256 i = 0; i < 10; i++) {
            uint256 idChild = reliquary.createRelicAndDeposit(address(this), 0, 10 ether);
            reliquary.shift(idParent, idChild, 1);
            reliquary.update(idParent, address(0));
            uint256 levelChild = reliquary.getPositionForId(idChild).level;
            assertEq(levelChild, 0); // assert max level
        }
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
    //         address(testToken),
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
    //         address(testToken),
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
