// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "contracts/Reliquary.sol";
import "contracts/emission_curves/Constant.sol";
import "contracts/nft_descriptors/NFTDescriptor.sol";

interface IERC20Mint {
    function mint(address to, uint amount) external;
}

contract ReliquaryTest is Test {
    using Strings for address;
    using Strings for uint;

    Reliquary reliquary;
    IERC20 oath;
    IERC20 weth;
    INFTDescriptor nftDescriptor;
    address constant WETH_WHALE = 0x2400BB4D7221bA530Daee061D5Afe219E9223Eae;

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
        oath = IERC20(0x21Ada0D2aC28C3A5Fa3cD2eE30882dA8812279B6);
        IEmissionCurve curve = IEmissionCurve(address(new Constant()));
        reliquary = new Reliquary(oath, curve);

        vm.prank(address(0x111731A388743a75CF60CCA7b140C58e41D83635));
        IERC20Mint(address(oath)).mint(address(reliquary), 100_000_000 ether);

        weth = IERC20(0x74b23882a30290451A17c44f4F05243b6b58C76d);
        nftDescriptor = INFTDescriptor(address(new NFTDescriptor(IReliquary(address(reliquary)))));

        uint[] memory requiredMaturity = new uint[](8);
        requiredMaturity[0] = 0;
        requiredMaturity[1] = 1 days;
        requiredMaturity[2] = 7 days;
        requiredMaturity[3] = 14 days;
        requiredMaturity[4] = 30 days;
        requiredMaturity[5] = 90 days;
        requiredMaturity[6] = 180 days;
        requiredMaturity[7] = 365 days;

        uint[] memory allocPoints = new uint[](8);
        allocPoints[0] = 100;
        allocPoints[1] = 120;
        allocPoints[2] = 150;
        allocPoints[3] = 200;
        allocPoints[4] = 300;
        allocPoints[5] = 400;
        allocPoints[6] = 500;
        allocPoints[7] = 750;

        reliquary.grantRole(keccak256(bytes("OPERATOR")), address(this));
        reliquary.addPool(
            100,
            weth,
            IRewarder(address(0)),
            requiredMaturity,
            allocPoints,
            "ETH Pool",
            nftDescriptor
        );

        vm.prank(WETH_WHALE);
        weth.approve(address(reliquary), type(uint).max);
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
            "AccessControl: account ", WETH_WHALE.toHexString(),
            " is missing role ", uint(keccak256(bytes("OPERATOR"))).toHexString()
        )));
        vm.prank(WETH_WHALE);
        reliquary.modifyPool(0, 100, IRewarder(address(0)), "USDC Pool", nftDescriptor, true);
    }

    function testPendingOath() public {
        vm.startPrank(WETH_WHALE);
        reliquary.createRelicAndDeposit(WETH_WHALE, 0, 1 ether);
        vm.warp(block.timestamp + 365 days);
        reliquary.updatePool(0);
        uint relicId = reliquary.tokenOfOwnerByIndex(WETH_WHALE, 0);
        reliquary.updatePosition(relicId);
        assertTrue(reliquary.pendingOath(relicId) == 3153600 ether);
        vm.stopPrank();
    }

    function testMassUpdatePools() public {
        vm.warp(block.timestamp + 1);
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

    function testCreateRelicAndDeposit() public {
        vm.expectEmit(true, true, true, true);
        emit Deposit(0, 1, WETH_WHALE, 1);
        vm.prank(WETH_WHALE);
        reliquary.createRelicAndDeposit(WETH_WHALE, 0, 1);
    }

    function testDepositExisting() public {
        vm.startPrank(WETH_WHALE);
        reliquary.createRelicAndDeposit(WETH_WHALE, 0, 1);
        uint relicId = reliquary.tokenOfOwnerByIndex(WETH_WHALE, 0);
        reliquary.deposit(2, relicId);
        vm.stopPrank();
        assertTrue(reliquary.getPositionForId(relicId).amount == 3);
    }

    function testRevertOnDepositInvalidPool() public {
        vm.expectRevert(bytes("invalid pool ID"));
        vm.prank(WETH_WHALE);
        reliquary.createRelicAndDeposit(WETH_WHALE, 1, 1);
    }

    function testWithdraw() public {
        vm.startPrank(WETH_WHALE);
        reliquary.createRelicAndDeposit(WETH_WHALE, 0, 1);
        uint relicId = reliquary.tokenOfOwnerByIndex(WETH_WHALE, 0);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(0, 1, WETH_WHALE, relicId);
        reliquary.withdraw(1, relicId);
        vm.stopPrank();
    }

    function testHarvest() public {
        vm.prank(WETH_WHALE);
        weth.transfer(address(1), 1.25 ether);

        vm.startPrank(address(1));
        weth.approve(address(reliquary), type(uint).max);
        reliquary.createRelicAndDeposit(address(1), 0, 1 ether);
        uint relicIdA = reliquary.tokenOfOwnerByIndex(address(1), 0);
        vm.warp(block.timestamp + 180 days);
        reliquary.withdraw(0.75 ether, relicIdA);
        reliquary.deposit(1 ether, relicIdA);
        vm.stopPrank();

        vm.startPrank(WETH_WHALE);
        reliquary.createRelicAndDeposit(WETH_WHALE, 0, 100 ether);
        uint relicIdB = reliquary.tokenOfOwnerByIndex(WETH_WHALE, 0);
        vm.warp(block.timestamp + 180 days);
        reliquary.harvest(relicIdB);
        vm.stopPrank();

        vm.prank(address(1));
        reliquary.harvest(relicIdA);

        assertTrue((oath.balanceOf(address(1)) + oath.balanceOf(WETH_WHALE)) / 1e18 == 3110399);
    }

    function testEmergencyWithdraw() public {
        vm.startPrank(WETH_WHALE);
        reliquary.createRelicAndDeposit(WETH_WHALE, 0, 100 ether);
        uint relicId = reliquary.tokenOfOwnerByIndex(WETH_WHALE, 0);
        vm.expectEmit(true, true, true, true);
        emit EmergencyWithdraw(0, 100 ether, WETH_WHALE, relicId);
        reliquary.emergencyWithdraw(relicId);
        vm.stopPrank();
    }
}
