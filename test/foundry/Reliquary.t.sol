// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "contracts/Reliquary.sol";
import "contracts/emission_curves/Constant.sol";
import "contracts/nft_descriptors/NFTDescriptor.sol";
import "contracts/test/TestToken.sol";
import "openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";

contract ReliquaryTest is ERC721Holder, Test {
    using Strings for address;
    using Strings for uint;

    Reliquary reliquary;
    TestToken oath;
    TestToken testToken;
    INFTDescriptor nftDescriptor;

    uint[] requiredMaturity = [0, 1 days, 7 days, 14 days, 30 days, 90 days, 180 days, 365 days];
    uint[] allocPoints = [100, 120, 150, 200, 300, 400, 500, 750];

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
    event LogPoolModified(
        uint indexed pid,
        uint allocPoint,
        IRewarder indexed rewarder,
        INFTDescriptor nftDescriptor
    );
    event LogUpdatePool(uint indexed pid, uint lastRewardTime, uint lpSupply, uint accOathPerShare);

    function setUp() public {
        oath = new TestToken("Oath Token", "OATH", 18);
        IEmissionCurve curve = IEmissionCurve(address(new Constant()));
        reliquary = new Reliquary(oath, curve);

        oath.mint(address(reliquary), 100_000_000 ether);

        testToken = new TestToken("Test Token", "TT", 6);
        nftDescriptor = INFTDescriptor(address(new NFTDescriptor(IReliquary(address(reliquary)))));

        reliquary.grantRole(keccak256(bytes("OPERATOR")), address(this));
        reliquary.addPool(
            100,
            testToken,
            IRewarder(address(0)),
            requiredMaturity,
            allocPoints,
            "ETH Pool",
            nftDescriptor
        );

        testToken.mint(address(this), 100_000_000 ether);
        testToken.approve(address(reliquary), type(uint).max);
    }

    function testPoolLength() public {
        assertTrue(reliquary.poolLength() == 1);
    }

    function testModifyPool() public {
        vm.expectEmit(true, true, false, true);
        emit LogPoolModified(0, 100, IRewarder(address(0)), nftDescriptor);
        reliquary.modifyPool(0, 100, IRewarder(address(0)), "USDC Pool", nftDescriptor, true);
    }

    function testRevertOnModifyInvalidPool() public {
        vm.expectRevert(bytes("set: pool does not exist"));
        reliquary.modifyPool(1, 100, IRewarder(address(0)), "USDC Pool", nftDescriptor, true);
    }

    function testRevertOnUnauthorized() public {
        vm.expectRevert(bytes(string.concat(
            "AccessControl: account ", address(1).toHexString(),
            " is missing role ", uint(keccak256(bytes("OPERATOR"))).toHexString()
        )));
        vm.prank(address(1));
        reliquary.modifyPool(0, 100, IRewarder(address(0)), "USDC Pool", nftDescriptor, true);
    }

    function testPendingOath(uint amount, uint time) public {
        vm.assume(time < 3650 days);
        amount = bound(amount, 1, testToken.balanceOf(address(this)));
        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, amount);
        skip(time);
        reliquary.updatePosition(relicId);
        assertApproxEqAbs(reliquary.pendingOath(relicId), time * 1e17, 1e16);
    }

    function testMassUpdatePools() public {
        skip(1);
        uint[] memory pools = new uint[](1);
        pools[0] = 0;
        vm.expectEmit(true, false, false, true);
        emit LogUpdatePool(0, block.timestamp, 0, 0);
        reliquary.massUpdatePools(pools);
    }

    function testRevertOnUpdateInvalidPool() public {
        uint[] memory pools = new uint[](2);
        pools[0] = 0;
        pools[1] = 1;
        vm.expectRevert(bytes("invalid pool ID"));
        reliquary.massUpdatePools(pools);
    }

    function testCreateRelicAndDeposit(uint amount) public {
        amount = bound(amount, 1, testToken.balanceOf(address(this)));
        vm.expectEmit(true, true, true, true);
        emit Deposit(0, amount, address(this), 1);
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
        vm.assume(pool != 0);
        vm.expectRevert(bytes("invalid pool ID"));
        reliquary.createRelicAndDeposit(address(this), pool, 1);
    }

    function testWithdraw(uint amount) public {
        amount = bound(amount, 1, testToken.balanceOf(address(this)));
        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, amount);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(0, amount, address(this), relicId);
        reliquary.withdraw(amount, relicId);
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
        reliquary.harvest(relicIdB);

        vm.startPrank(address(1));
        reliquary.harvest(relicIdA);
        vm.stopPrank();

        assertEq((oath.balanceOf(address(1)) + oath.balanceOf(address(this))) / 1e18, 3110399);
    }

    function testEmergencyWithdraw(uint amount) public {
        amount = bound(amount, 1, testToken.balanceOf(address(this)));
        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, amount);
        vm.expectEmit(true, true, true, true);
        emit EmergencyWithdraw(0, amount, address(this), relicId);
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

    function testShift(uint depositAmount1, uint depositAmount2, uint shiftAmount) public {
        depositAmount1 = bound(depositAmount1, 1, testToken.balanceOf(address(this)));
        depositAmount2 = bound(depositAmount2, 1, testToken.balanceOf(address(this)) - depositAmount1);
        shiftAmount = bound(shiftAmount, 1, depositAmount1);
        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount1);
        uint newRelicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount2);
        reliquary.shift(relicId, newRelicId, shiftAmount);
        assertEq(reliquary.getPositionForId(relicId).amount, depositAmount1 - shiftAmount);
        assertEq(reliquary.getPositionForId(newRelicId).amount, depositAmount2 + shiftAmount);
    }

    function testMerge(uint depositAmount1, uint depositAmount2) public {
        depositAmount1 = bound(depositAmount1, 1, testToken.balanceOf(address(this)));
        depositAmount2 = bound(depositAmount2, 1, testToken.balanceOf(address(this)) - depositAmount1);
        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount1);
        uint newRelicId = reliquary.createRelicAndDeposit(address(this), 0, depositAmount2);
        reliquary.merge(relicId, newRelicId);
        assertEq(reliquary.getPositionForId(newRelicId).amount, depositAmount1 + depositAmount2);
    }
}
