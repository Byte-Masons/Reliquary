// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/mocks/ERC20DecimalsMock.sol";
import "openzeppelin-contracts/contracts/mocks/ERC4626Mock.sol";
import "openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import "contracts/emission_curves/Constant.sol";
import "contracts/helpers/DepositHelperERC4626.sol";
import "contracts/nft_descriptors/NFTDescriptorSingle4626.sol";
import "contracts/Reliquary.sol";
import "contracts/rewarders/RollingRewarder.sol";
import "contracts/rewarders/ParentRewarder-Rolling.sol";
import "contracts/rewarders/RewardsPool.sol";

contract MultipleRollingRewarderTest is ERC721Holder, Test {
    Reliquary reliquary;
    RollingRewarder rollingRewarderETH;
    RollingRewarder rollingRewarderUSDC;
    ERC20DecimalsMock grain;
    ERC20DecimalsMock depositToken; //BPT
    ERC20DecimalsMock rewardToken1; //WETH
    ERC20DecimalsMock rewardToken2; //USDC
    ParentRewarderRolling parent;
    RewardsPool rewardsPoolETH;
    RewardsPool rewardsPoolUSDC;

    uint[] requiredMaturity = [0, 7 days, 14 days, 21 days, 28 days, 90 days, 180 days, 365 days];
    uint[] levelMultipliers = [100, 120, 150, 200, 300, 400, 500, 750];

    function setUp() public {
        grain = new ERC20DecimalsMock("Grain", "GRAIN", 18);
        depositToken = new ERC20DecimalsMock("Grain-BPT", "BPT", 18);
        rewardToken1 = new ERC20DecimalsMock("WETH", "WETH", 18);
        rewardToken2 = new ERC20DecimalsMock("USDC", "USDC", 6);

        reliquary = new Reliquary(
            address(grain),
            address(new Constant()),
            "Reliquary Deposit",
            "RELIC"
        );

        reliquary.addPool(
            1000, address(depositToken), address(0), requiredMaturity, levelMultipliers, "whole-grain", address(0), true
        );

        uint256 pid =  reliquary.poolLength() - 1;

        parent = new ParentRewarderRolling(
            address(reliquary),
            pid
            );       

        parent.grantRole(keccak256("CHILD_SETTER"), address(this));
        parent.grantRole(keccak256("REWARD_SETTER"), address(this));
        reliquary.grantRole(keccak256("OPERATOR"), address(this));
        reliquary.modifyPool(0, 1000, address(parent), "whole-grain", address(0), true);
        rollingRewarderETH = RollingRewarder(parent.createChild(address(rewardToken1), address(this)));
        rollingRewarderUSDC = RollingRewarder(parent.createChild(address(rewardToken2), address(this)));
        
        grain.mint(address(this), 100_000 ether);
        grain.mint(address(reliquary), 100_000 ether);
        grain.approve(address(reliquary), type(uint).max);

        rewardsPoolUSDC = new RewardsPool(address(rewardToken2), address(rollingRewarderUSDC));
        rewardsPoolETH = new RewardsPool(address(rewardToken1), address(rollingRewarderETH));
    
        parent.setChildsRewardPool(address(rollingRewarderETH), address(rewardsPoolETH));
        parent.setChildsRewardPool(address(rollingRewarderUSDC), address(rewardsPoolUSDC));
    
    }

    function testPoolLength() public {
        assertTrue(reliquary.poolLength() == 1);
    }

    function testCorrectNumberOfChildren() public {
        address[] memory children = parent.getChildrenRewarders();
        assertTrue(children.length == 2);
    }

    function testDeposit() public {
        depositToken.mint(address(this), 100 ether);
        depositToken.approve(address(reliquary), type(uint).max);
        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, 100 ether);

        assertEq(reliquary.balanceOf(address(this)), 1, "no Relic given");
        assertEq(reliquary.getPositionForId(relicId).amount, 100 ether, "deposited amount not expected amount");
    }

    function testEmissions() public {
        uint256 ethReward = 1 ether;
        uint256 usdcReward = 1000 * 10**6;

        //Fund the rewarders
        rewardToken1.mint(address(rewardsPoolETH), ethReward);
        rewardToken2.mint(address(rewardsPoolUSDC), usdcReward);

        //Call Fund on the pools
        rewardsPoolETH.fundRewarder();
        rewardsPoolUSDC.fundRewarder();
    
        depositToken.mint(address(this), 100 ether);
        depositToken.approve(address(reliquary), type(uint).max);
        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, 100 ether);
        
        skip(7 days);

        reliquary.harvest(relicId, address(this));

        uint256 earnedEth = IERC20(rewardToken1).balanceOf(address(this));
        uint256 earnedUsdc = IERC20(rewardToken2).balanceOf(address(this));
        assertApproxEqAbs(earnedEth, ethReward, 1e5);
        assertApproxEqAbs(earnedUsdc, usdcReward, 1e5);
    }

    function testDistribution() public {
        parent.removeChild(address(rollingRewarderUSDC));
        rewardToken1.mint(address(rewardsPoolETH), 10 ether);
        rewardsPoolETH.fundRewarder();

        address user1 = makeAddr("user1");
        depositToken.mint(user1, 100 ether);

        vm.startPrank(user1);
        depositToken.approve(address(reliquary), type(uint).max);
        reliquary.createRelicAndDeposit(user1, 0, 100 ether);
        vm.stopPrank();

        skip(3.5 days);

        address user2 = makeAddr("user2");
        depositToken.mint(user2, 100 ether);

        vm.startPrank(user2);
        depositToken.approve(address(reliquary), type(uint).max);
        reliquary.createRelicAndDeposit(user2, 0, 100 ether);
        vm.stopPrank();

        skip(3.5 days);

        vm.prank(user1);
        reliquary.harvest(1, user1);

        vm.prank(user2);
        reliquary.harvest(2, user2);

        uint256 rewardUser1 = IERC20(rewardToken1).balanceOf(user1);
        uint256 rewardUser2 = IERC20(rewardToken1).balanceOf(user2);

        assertApproxEqAbs(rewardUser1, 7.5 ether, 1e5, "user1 reward not expected");
        assertApproxEqAbs(rewardUser2, 2.5 ether, 1e5, "user2 reward not expected");

        rewardToken1.mint(address(rewardsPoolETH), 10 ether);
        rewardsPoolETH.fundRewarder();

        vm.startPrank(user2);
        reliquary.withdraw(100 ether, 2);
        reliquary.createRelicAndDeposit(user2, 0, 100 ether);
        vm.stopPrank();

        skip(7 days);

        vm.prank(user1);
        reliquary.harvest(1, user1);

        rewardUser1 = IERC20(rewardToken1).balanceOf(user1) - rewardUser1;
        // factor in maturity = 20% boost for user1
        // 220 is the calculated pool size with multipliers
        assertApproxEqAbs(rewardUser1, 10 ether * uint(120) / 220, 1e5, "user1 reward not expected");
    }

    function testSplit() public {
        rewardToken1.mint(address(rewardsPoolETH), 10 ether);
        rewardsPoolETH.fundRewarder();

        depositToken.mint(address(this), 100 ether);
        depositToken.approve(address(reliquary), type(uint).max);
        reliquary.createRelicAndDeposit(address(this), 0, 100 ether);

        skip(7 days);

        address user1 = makeAddr("user1");
        depositToken.mint(user1, 120 ether); // simulate the 20% maturity boost that the other positions got
        vm.startPrank(user1);
        depositToken.approve(address(reliquary), type(uint).max);
        reliquary.createRelicAndDeposit(user1, 0, 100 ether);
        vm.stopPrank();
        
        reliquary.split(1, 50 ether, address(this));

        rewardToken1.mint(address(rewardsPoolETH), 20 ether);
        rewardsPoolETH.fundRewarder();
        skip(7 days);

        reliquary.harvest(1, address(this));

        uint256 rewardRelic1 = IERC20(rewardToken1).balanceOf(address(this));
        assertApproxEqAbs(rewardRelic1, 10 ether + 5 ether, 1e5, "reward not expected");

        reliquary.harvest(3, address(this));
        uint256 rewardRelic2 = IERC20(rewardToken1).balanceOf(address(this)) - rewardRelic1;
        assertApproxEqAbs(rewardRelic2, 5 ether, 1e5, "reward not expected");
    }

    function testMerge() public {
        rewardToken1.mint(address(rewardsPoolETH), 10 ether);
        rewardsPoolETH.fundRewarder();

        depositToken.mint(address(this), 100 ether);
        depositToken.approve(address(reliquary), type(uint).max);
        reliquary.createRelicAndDeposit(address(this), 0, 100 ether);

        address user1 = makeAddr("user1");
        depositToken.mint(user1, 200 ether);
        vm.startPrank(user1);
        depositToken.approve(address(reliquary), type(uint).max);
        reliquary.createRelicAndDeposit(user1, 0, 100 ether);
        vm.stopPrank();
        
        skip(7 days);
        reliquary.harvest(1, address(this));

        vm.startPrank(user1);
        reliquary.createRelicAndDeposit(user1, 0, 100 ether);
        reliquary.merge(2, 3);
        vm.stopPrank();

        rewardToken1.mint(address(rewardsPoolETH), 10 ether);
        rewardsPoolETH.fundRewarder();
        skip(7 days);
        
        vm.prank(user1);
        reliquary.harvest(3, user1);

        uint256 rewardMergedRelic = IERC20(rewardToken1).balanceOf(user1);
        assertApproxEqAbs(
            rewardMergedRelic,
            5 ether + (10 ether * uint(200) / 320),
            1e5,
            "reward not expected"
        );
    }

    function testShift() public {
        rewardToken1.mint(address(rewardsPoolETH), 10 ether);
        rewardsPoolETH.fundRewarder();

        depositToken.mint(address(this), 100 ether);
        depositToken.approve(address(reliquary), type(uint).max);
        reliquary.createRelicAndDeposit(address(this), 0, 100 ether);

        address user1 = makeAddr("user1");
        depositToken.mint(user1, 200 ether);
        vm.startPrank(user1);
        depositToken.approve(address(reliquary), type(uint).max);
        reliquary.createRelicAndDeposit(user1, 0, 100 ether);
        vm.stopPrank();
        
        skip(7 days);
        reliquary.harvest(1, address(this));

        vm.startPrank(user1);
        reliquary.createRelicAndDeposit(user1, 0, 100 ether);
        reliquary.shift(2, 3, 100 ether);
        vm.stopPrank();

        rewardToken1.mint(address(rewardsPoolETH), 10 ether);
        rewardsPoolETH.fundRewarder();
        skip(7 days);

        vm.startPrank(user1);
        reliquary.harvest(3, user1);
        reliquary.harvest(2, user1);
        vm.stopPrank();

        uint256 rewardMergedRelic = IERC20(rewardToken1).balanceOf(user1);
        assertApproxEqAbs(
            rewardMergedRelic,
            5 ether + (10 ether * uint(200) / 320),
            1e5,
            "reward not expected"
        );
    }

}
