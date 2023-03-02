// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "contracts/Reliquary.sol";
import "contracts/emission_curves/Constant.sol";
import "contracts/nft_descriptors/NFTDescriptor.sol";
import "contracts/rewarders/DepositBonusRewarder.sol";
import "contracts/rewarders/ParentRewarder.sol";
import "openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";
import "openzeppelin-contracts/contracts/mocks/ERC20DecimalsMock.sol";

contract ReliquaryTest is ERC721Holder, Test {
    using Strings for address;
    using Strings for uint;

    Reliquary reliquary;
    ERC20DecimalsMock oath;
    ERC20DecimalsMock testToken;
    address nftDescriptor;

    uint[] requiredMaturity = [0, 1 days, 7 days, 14 days, 30 days, 90 days, 180 days, 365 days];
    uint[] allocPoints = [100, 120, 150, 200, 300, 400, 500, 750];

    function setUp() public {
        oath = new ERC20DecimalsMock("Oath Token", "OATH", 18);
        address curve = address(new Constant());
        reliquary = new Reliquary(address(oath), curve, "Reliquary Deposit", "RELIC");

        oath.mint(address(reliquary), 100_000_000 ether);

        testToken = new ERC20DecimalsMock("Test Token", "TT", 6);
        nftDescriptor = address(new NFTDescriptor(address(reliquary)));

        reliquary.grantRole(keccak256("OPERATOR"), address(this));
        reliquary.addPool(
            100, address(testToken), address(0), requiredMaturity, allocPoints, "ETH Pool", nftDescriptor, true
        );

        testToken.mint(address(this), 100_000_000 ether);
        testToken.approve(address(reliquary), type(uint).max);
    }

    function testPoolLength() public {
        assertTrue(reliquary.poolLength() == 1);
    }

    function testModifyPool() public {
        vm.expectEmit(true, true, false, true);
        emit ReliquaryEvents.LogPoolModified(0, 100, address(0), nftDescriptor);
        reliquary.modifyPool(0, 100, address(0), "USDC Pool", nftDescriptor, true);
    }

    function testRevertOnModifyInvalidPool() public {
        vm.expectRevert(Reliquary.NonExistentPool.selector);
        reliquary.modifyPool(1, 100, address(0), "USDC Pool", nftDescriptor, true);
    }

    function testRevertOnModifyPoolUnauthorized() public {
        vm.expectRevert(
            bytes(
                string.concat(
                    "AccessControl: account ",
                    address(1).toHexString(),
                    " is missing role ",
                    uint(keccak256("OPERATOR")).toHexString()
                )
            )
        );
        vm.prank(address(1));
        reliquary.modifyPool(0, 100, address(0), "USDC Pool", nftDescriptor, true);
    }

    function testPendingOath(uint amount, uint time) public {
        time = bound(time, 0, 3650 days);
        amount = bound(amount, 1, testToken.balanceOf(address(this)));
        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, amount);
        skip(time);
        reliquary.updatePosition(relicId);
        assertApproxEqAbs(reliquary.pendingReward(relicId), time * 1e17, 1e16);
    }

    function testMassUpdatePools() public {
        skip(1);
        uint[] memory pools = new uint[](1);
        pools[0] = 0;
        vm.expectEmit(true, false, false, true);
        emit ReliquaryEvents.LogUpdatePool(0, block.timestamp, 0, 0);
        reliquary.massUpdatePools(pools);
    }

    function testRevertOnUpdateInvalidPool() public {
        uint[] memory pools = new uint[](2);
        pools[0] = 0;
        pools[1] = 1;
        vm.expectRevert(Reliquary.NonExistentPool.selector);
        reliquary.massUpdatePools(pools);
    }

    function testCreateRelicAndDeposit(uint amount) public {
        amount = bound(amount, 1, testToken.balanceOf(address(this)));
        vm.expectEmit(true, true, true, true);
        emit ReliquaryEvents.Deposit(0, amount, address(this), 1);
        reliquary.createRelicAndDeposit(address(this), 0, amount);
    }

    function testDepositExisting(uint amountA, uint amountB) public {
        amountA = bound(amountA, 1, type(uint).max / 2);
        amountB = bound(amountB, 1, type(uint).max / 2);
        vm.assume(amountA + amountB <= testToken.balanceOf(address(this)));
        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, amountA);
        reliquary.deposit(amountB, relicId);
        assertEq(reliquary.getPositionForId(relicId).amount, amountA + amountB);
    }

    function testRevertOnDepositInvalidPool(uint pool) public {
        pool = bound(pool, 1, type(uint).max);
        vm.expectRevert(Reliquary.NonExistentPool.selector);
        reliquary.createRelicAndDeposit(address(this), pool, 1);
    }

    function testRevertOnDepositUnauthorized() public {
        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, 1);
        vm.expectRevert(Reliquary.NotApprovedOrOwner.selector);
        vm.prank(address(1));
        reliquary.deposit(1, relicId);
    }

    function testWithdraw(uint amount) public {
        amount = bound(amount, 1, testToken.balanceOf(address(this)));
        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, amount);
        vm.expectEmit(true, true, true, true);
        emit ReliquaryEvents.Withdraw(0, amount, address(this), relicId);
        reliquary.withdraw(amount, relicId);
    }

    function testRevertOnWithdrawUnauthorized() public {
        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, 1);
        vm.expectRevert(Reliquary.NotApprovedOrOwner.selector);
        vm.prank(address(1));
        reliquary.withdraw(1, relicId);
    }

    function testHarvest() public {
        testToken.transfer(address(1), 1.25 ether);

        vm.startPrank(address(1));
        testToken.approve(address(reliquary), type(uint).max);
        uint relicIdA = reliquary.createRelicAndDeposit(address(1), 0, 1 ether);
        skip(180 days);
        reliquary.withdraw(0.75 ether, relicIdA);
        reliquary.deposit(1 ether, relicIdA);

        vm.stopPrank();
        uint relicIdB = reliquary.createRelicAndDeposit(address(this), 0, 100 ether);
        skip(180 days);
        reliquary.harvest(relicIdB, address(this));

        vm.startPrank(address(1));
        reliquary.harvest(relicIdA, address(this));
        vm.stopPrank();

        assertEq((oath.balanceOf(address(1)) + oath.balanceOf(address(this))) / 1e18, 3110399);
    }

    function testRevertOnHarvestUnauthorized() public {
        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, 1);
        vm.expectRevert(Reliquary.NotApprovedOrOwner.selector);
        vm.prank(address(1));
        reliquary.harvest(relicId, address(this));
    }

    function testEmergencyWithdraw(uint amount) public {
        amount = bound(amount, 1, testToken.balanceOf(address(this)));
        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, amount);
        vm.expectEmit(true, true, true, true);
        emit ReliquaryEvents.EmergencyWithdraw(0, amount, address(this), relicId);
        reliquary.emergencyWithdraw(relicId);
    }

    function testRevertOnEmergencyWithdrawNotOwner() public {
        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, 1);
        vm.expectRevert(Reliquary.NotOwner.selector);
        vm.prank(address(1));
        reliquary.emergencyWithdraw(relicId);
    }

    function testSplit(uint depositAmount, uint splitAmount) public {
        depositAmount = bound(depositAmount, 1, testToken.balanceOf(address(this)));
        splitAmount = bound(splitAmount, 1, depositAmount);

        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount);
        uint newRelicId = reliquary.split(relicId, splitAmount, address(this));

        assertEq(reliquary.balanceOf(address(this)), 2);
        assertEq(reliquary.getPositionForId(relicId).amount, depositAmount - splitAmount);
        assertEq(reliquary.getPositionForId(newRelicId).amount, splitAmount);
    }

    function testRevertOnSplitUnderflow(uint depositAmount, uint splitAmount) public {
        depositAmount = bound(depositAmount, 1, testToken.balanceOf(address(this)) / 2 - 1);
        splitAmount = bound(splitAmount, depositAmount + 1, testToken.balanceOf(address(this)) - depositAmount);

        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount);
        vm.expectRevert(stdError.arithmeticError);
        reliquary.split(relicId, splitAmount, address(this));
    }

    function testShift(uint depositAmount1, uint depositAmount2, uint shiftAmount) public {
        depositAmount1 = bound(depositAmount1, 1, testToken.balanceOf(address(this)) - 1);
        depositAmount2 = bound(depositAmount2, 1, testToken.balanceOf(address(this)) - depositAmount1);
        shiftAmount = bound(shiftAmount, 1, depositAmount1);

        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount1);
        uint newRelicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount2);
        reliquary.shift(relicId, newRelicId, shiftAmount);

        assertEq(reliquary.getPositionForId(relicId).amount, depositAmount1 - shiftAmount);
        assertEq(reliquary.getPositionForId(newRelicId).amount, depositAmount2 + shiftAmount);
    }

    function testRevertOnShiftUnderflow(uint depositAmount, uint shiftAmount) public {
        depositAmount = bound(depositAmount, 1, testToken.balanceOf(address(this)) / 2 - 1);
        shiftAmount = bound(shiftAmount, depositAmount + 1, testToken.balanceOf(address(this)) - depositAmount);

        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount);
        uint newRelicId = reliquary.createRelicAndDeposit(address(this), 0, 1);
        vm.expectRevert(stdError.arithmeticError);
        reliquary.shift(relicId, newRelicId, shiftAmount);
    }

    function testMerge(uint depositAmount1, uint depositAmount2) public {
        depositAmount1 = bound(depositAmount1, 1, testToken.balanceOf(address(this)) - 1);
        depositAmount2 = bound(depositAmount2, 1, testToken.balanceOf(address(this)) - depositAmount1);

        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount1);
        uint newRelicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount2);
        reliquary.merge(relicId, newRelicId);

        assertEq(reliquary.getPositionForId(newRelicId).amount, depositAmount1 + depositAmount2);
    }

    function testCompareDepositAndMerge(uint amount1, uint amount2, uint32 time) public {
        amount1 = bound(amount1, 1, testToken.balanceOf(address(this)) - 1);
        amount2 = bound(amount2, 1, testToken.balanceOf(address(this)) - amount1);

        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, amount1);
        skip(time);
        reliquary.deposit(amount2, relicId);
        uint maturity1 = block.timestamp - reliquary.getPositionForId(relicId).entry;

        //reset maturity
        reliquary.withdraw(amount1 + amount2, relicId);
        reliquary.deposit(amount1, relicId);

        skip(time);
        uint newRelicId = reliquary.createRelicAndDeposit(address(this), 0, amount2);
        reliquary.merge(newRelicId, relicId);
        uint maturity2 = block.timestamp - reliquary.getPositionForId(relicId).entry;

        assertApproxEqAbs(maturity1, maturity2, 1);
    }

    function testMergeAfterSplit() public {
        uint depositAmount1 = 100 ether;
        uint depositAmount2 = 50 ether;
        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount1);
        skip(2 days);
        reliquary.harvest(relicId, address(this));
        reliquary.split(relicId, 50 ether, address(this));
        uint newRelicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount2);
        reliquary.merge(relicId, newRelicId);
        assertEq(reliquary.getPositionForId(newRelicId).amount, 100 ether);
    }

    function testBurn() public {
        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, 1 ether);
        vm.expectRevert(Reliquary.BurningPrincipal.selector);
        reliquary.burn(relicId);

        reliquary.withdrawAndHarvest(1 ether, relicId, address(this));
        vm.expectRevert(bytes("ERC721: caller is not token owner or approved"));
        vm.prank(address(1));
        reliquary.burn(relicId);
        assertEq(reliquary.balanceOf(address(this)), 1);

        reliquary.burn(relicId);
        assertEq(reliquary.balanceOf(address(this)), 0);
    }

    function testDepositBonusRewarder() public {
        DepositBonusRewarder rewarder = new DepositBonusRewarder(
            1000 ether,
            1 ether,
            1 days,
            address(oath),
            address(reliquary)
        );
        oath.mint(address(rewarder), 1_000_000 ether);

        reliquary.addPool(
            100, address(testToken), address(rewarder), requiredMaturity, allocPoints, "ETH Pool", nftDescriptor, true
        );

        uint relicId = reliquary.createRelicAndDeposit(address(this), 1, 1 ether);
        skip(1 days);
        rewarder.claimDepositBonus(relicId, address(this));

        assertEq(oath.balanceOf(address(this)), 1000 ether);
    }

    function testParentRewarder() public {
        ERC20DecimalsMock parentToken = new ERC20DecimalsMock("Parent Token", "PT", 18);
        ParentRewarder parent = new ParentRewarder(5e17, address(parentToken), address(reliquary));
        parentToken.mint(address(parent), 1_000_000 ether);
        parent.grantRole(keccak256("CHILD_SETTER"), address(this));

        ERC20DecimalsMock childToken = new ERC20DecimalsMock("Child Token", "CT", 6);
        address child = parent.createChild(address(childToken), 2e6, address(this));
        childToken.mint(child, 1_000_000 ether);

        reliquary.addPool(
            100, address(testToken), address(parent), requiredMaturity, allocPoints, "ETH Pool", nftDescriptor, true
        );

        uint relicId = reliquary.createRelicAndDeposit(address(this), 1, 1 ether);
        skip(1 days);
        reliquary.harvest(relicId, address(this));

        assertEq(oath.balanceOf(address(this)), 4320 ether);
        assertEq(parentToken.balanceOf(address(this)), 2160 ether);
        assertEq(childToken.balanceOf(address(this)), 8640e6);
    }
}
