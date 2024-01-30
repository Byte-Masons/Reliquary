// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/mocks/ERC20DecimalsMock.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/contracts/mocks/ERC4626Mock.sol";
import "openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";
import "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import "contracts/emission_curves/Constant.sol";
import "contracts/helpers/DepositHelperERC4626.sol";
import "contracts/nft_descriptors/NFTDescriptorSingle4626.sol";
import "contracts/Reliquary.sol";
import "contracts/rewarders/RollingRewarder.sol";
import "contracts/rewarders/ParentRewarder-Rolling.sol";
import "contracts/rewarders/RewardsPool.sol";
import "contracts/interfaces/IVoter.sol";
import "contracts/interfaces/IGauge.sol";
import "contracts/interfaces/IPairFactory.sol";
import "contracts/interfaces/IPair.sol";
import "contracts/interfaces/IWETH.sol";
import "contracts/interfaces/IRouter01.sol";

import "forge-std/console.sol";


contract ReliquaryDoubleStaking is ERC721Holder, Test {
    Reliquary reliquary;
    RollingRewarder rollingRewarderOHBR;
    RollingRewarder rollingRewarderUSDT;
    IERC20Metadata harborToken;
    IWETH counterAsset;
    ERC20DecimalsMock rewardToken1; //oHBR
    ERC20DecimalsMock rewardToken2; //USDT
    IERC20Metadata thenaToken;
    ParentRewarderRolling parent;
    RewardsPool rewardsPoolOHBR;
    RewardsPool rewardsPoolUSDT;
    IVoter voter;
    IGauge gauge;
    IPairFactory pairFactory;
    IPair poolToken;
    address internal thenaReceiver;
    address constant veNFT = 0xfBBF371C9B0B994EebFcC977CEf603F7f31c070D;

    uint[] requiredMaturity = [0, 7 days, 14 days, 21 days, 28 days, 90 days, 180 days, 365 days];
    uint[] levelMultipliers = [100, 120, 150, 200, 300, 400, 500, 750];

    function setUp() public {
        vm.createSelectFork("binance", 35652076);

        harborToken = IERC20Metadata(0xa045E37a0D1dd3A45fefb8803D22457abc0A728a); // GHNY
        counterAsset = IWETH(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c); // WBNB
        hoax(address(this));


        voter = IVoter(0x3A1D0952809F4948d15EBCe8d345962A282C4fCb);
        vm.label(address(voter), "Voter");
        thenaToken = IERC20Metadata(0xF4C8E32EaDEC4BFe97E0F595AdD0f4450a863a11);
        vm.label(address(thenaToken), "Thena Token");

        poolToken = IPair(0xA97E46DC17e2b678e5f049A2670fAe000b57F05E);
        gauge = IGauge(0xe1aD94646E9866d48cca59080535eF782d03B4af);
        vm.label(address(gauge), "Gauge");

        rewardToken1 = new ERC20DecimalsMock("Harbor oToken", "oHBR", 18);
        vm.label(address(rewardToken1), "oHBR");
        rewardToken2 = new ERC20DecimalsMock("USDT", "USDT", 18);
        vm.label(address(rewardToken2), "USDT");

        thenaReceiver = payable(address(uint160(uint256(keccak256(abi.encodePacked("thena receiver"))))));
        vm.label(thenaReceiver, "thenaReceiver");

        reliquary = new Reliquary(
            address(rewardToken1), // oHBR
            address(new Constant()),
            address(thenaToken),
            address(voter),
            thenaReceiver,
            "Reliquary Deposit",
            "RELIC"
        );

        reliquary.grantRole(keccak256(bytes("OPERATOR")), address(this));

        reliquary.addPool(
            1000, address(poolToken), address(0), requiredMaturity, levelMultipliers, "harbor-staking", address(0), true
        );

        uint256 pid = reliquary.poolLength() - 1;

        parent = new ParentRewarderRolling(
            0,
            address(rewardToken1),
            address(reliquary),
            pid
        );       

        parent.grantRole(keccak256("CHILD_SETTER"), address(this));
        parent.grantRole(keccak256("REWARD_SETTER"), address(this));
        reliquary.grantRole(keccak256("OPERATOR"), address(this));
        reliquary.modifyPool(0, 1000, address(parent), "harbor-staking", address(0), true);
        rollingRewarderOHBR = RollingRewarder(parent.createChild(address(rewardToken1), address(this)));
        rollingRewarderUSDT = RollingRewarder(parent.createChild(address(rewardToken2), address(this)));
        
        rewardsPoolUSDT = new RewardsPool(address(rewardToken2), address(rollingRewarderUSDT));
        rewardsPoolOHBR = new RewardsPool(address(rewardToken1), address(rollingRewarderOHBR));
    
        parent.setChildsRewardPool(address(rollingRewarderOHBR), address(rewardsPoolOHBR));
        parent.setChildsRewardPool(address(rollingRewarderUSDT), address(rewardsPoolUSDT));
    }

    function testPoolLength() public {
        assertTrue(reliquary.poolLength() == 1);
    }

    function testCorrectNumberOfChildren() public {
        address[] memory children = parent.getChildrenRewarders();
        assertTrue(children.length == 2);
    }

    function testDeposit() public {
        counterAsset.deposit{value: 1 ether}();

        vm.prank(0x981B04CBDCEE0C510D331fAdc7D6836a77085030); // GHNY admin
        IAccessControl(address(harborToken)).grantRole(
            0x60400965d90814aa36ab657cbeca3e3b701e320f6373ae1db85824fee2a79822, // Bridge minting role
            address(this)
        );
        vm.prank(address(this));
        ERC20DecimalsMock(address(harborToken)).mint(address(this), 10 ether);

        harborToken.transfer(address(poolToken), 10 ether);
        IERC20Metadata(address(counterAsset)).transfer(address(poolToken), 1 ether);
        poolToken.mint(address(this));

        uint256 balance = IERC20Metadata(address(poolToken)).balanceOf(address(this));

        IERC20Metadata(address(poolToken)).approve(address(reliquary), type(uint).max);
        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, balance);
 
        assertEq(gauge.balanceOf(address(reliquary)), balance, "lp tokens not in gauge");
        assertEq(reliquary.balanceOf(address(this)), 1, "no Relic given");
        assertEq(reliquary.getPositionForId(relicId).amount, balance, "deposited amount not expected amount");
    }

    function testEmissions() public {
        uint256 ohbrReward = 1 ether;
        uint256 usdtReward = 1 ether;

        //Fund the rewarders
        rewardToken1.mint(address(rewardsPoolOHBR), ohbrReward);
        rewardToken2.mint(address(rewardsPoolUSDT), usdtReward);

        //Call Fund on the pools
        rewardsPoolOHBR.fundRewarder();
        rewardsPoolUSDT.fundRewarder();
    
        //DEPOSIT
        counterAsset.deposit{value: 1 ether}();
        vm.prank(0x981B04CBDCEE0C510D331fAdc7D6836a77085030); // GHNY admin
        IAccessControl(address(harborToken)).grantRole(
            0x60400965d90814aa36ab657cbeca3e3b701e320f6373ae1db85824fee2a79822, // Bridge minting role
            address(this)
        );
        vm.prank(address(this));
        ERC20DecimalsMock(address(harborToken)).mint(address(this), 10 ether);
        harborToken.transfer(address(poolToken), 10 ether);
        IERC20Metadata(address(counterAsset)).transfer(address(poolToken), 1 ether);
        poolToken.mint(address(this));
        uint256 balance = IERC20Metadata(address(poolToken)).balanceOf(address(this));
        IERC20Metadata(address(poolToken)).approve(address(reliquary), type(uint).max);
        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, balance);
        
        skip(7 days);

        reliquary.harvest(relicId, address(this));

        uint256 earnedOhbr = IERC20(rewardToken1).balanceOf(address(this));
        uint256 earnedUsdt = IERC20(rewardToken2).balanceOf(address(this));
        assertApproxEqAbs(earnedOhbr, ohbrReward, 1e5);
        assertApproxEqAbs(earnedUsdt, usdtReward, 1e5);
    }

    function testDistribution() public {
        parent.removeChild(address(rollingRewarderUSDT));
        rewardToken1.mint(address(rewardsPoolOHBR), 10 ether);
        rewardsPoolOHBR.fundRewarder();

        address user1 = makeAddr("user1");
        deal(address(poolToken), user1, 100 ether);

        vm.startPrank(user1);
        IERC20Metadata(address(poolToken)).approve(address(reliquary), type(uint).max);
        reliquary.createRelicAndDeposit(user1, 0, 100 ether);
        vm.stopPrank();

        skip(3.5 days);

        address user2 = makeAddr("user2");
        deal(address(poolToken), user2, 100 ether);

        vm.startPrank(user2);
        IERC20Metadata(address(poolToken)).approve(address(reliquary), type(uint).max);
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

        rewardToken1.mint(address(rewardsPoolOHBR), 10 ether);
        rewardsPoolOHBR.fundRewarder();

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
        rewardToken1.mint(address(rewardsPoolOHBR), 10 ether);
        rewardsPoolOHBR.fundRewarder();

        deal(address(poolToken), address(this), 100 ether);
        IERC20Metadata(address(poolToken)).approve(address(reliquary), type(uint).max);
        reliquary.createRelicAndDeposit(address(this), 0, 100 ether);

        skip(7 days);

        address user1 = makeAddr("user1");
        deal(address(poolToken), user1, 120 ether); // simulate the 20% maturity boost that the other positions got
        vm.startPrank(user1);
        IERC20Metadata(address(poolToken)).approve(address(reliquary), type(uint).max);
        reliquary.createRelicAndDeposit(user1, 0, 100 ether);
        vm.stopPrank();
        
        reliquary.split(1, 50 ether, address(this));

        rewardToken1.mint(address(rewardsPoolOHBR), 20 ether);
        rewardsPoolOHBR.fundRewarder();
        skip(7 days);

        reliquary.harvest(1, address(this));

        uint256 rewardRelic1 = IERC20(rewardToken1).balanceOf(address(this));
        assertApproxEqAbs(rewardRelic1, 10 ether + 5 ether, 1e5, "reward not expected");

        reliquary.harvest(3, address(this));
        uint256 rewardRelic2 = IERC20(rewardToken1).balanceOf(address(this)) - rewardRelic1;
        assertApproxEqAbs(rewardRelic2, 5 ether, 1e5, "reward not expected");
    }

    function testMerge() public {
        rewardToken1.mint(address(rewardsPoolOHBR), 10 ether);
        rewardsPoolOHBR.fundRewarder();

        deal(address(poolToken), address(this), 100 ether);
        IERC20Metadata(address(poolToken)).approve(address(reliquary), type(uint).max);
        reliquary.createRelicAndDeposit(address(this), 0, 100 ether);

        address user1 = makeAddr("user1");
        deal(address(poolToken), user1, 200 ether);
        vm.startPrank(user1);
        IERC20Metadata(address(poolToken)).approve(address(reliquary), type(uint).max);
        reliquary.createRelicAndDeposit(user1, 0, 100 ether);
        vm.stopPrank();
        
        skip(7 days);
        reliquary.harvest(1, address(this));

        vm.startPrank(user1);
        reliquary.createRelicAndDeposit(user1, 0, 100 ether);
        reliquary.merge(2, 3);

        rewardToken1.mint(address(rewardsPoolOHBR), 10 ether);
        rewardsPoolOHBR.fundRewarder();

        skip(7 days);
        reliquary.harvest(3, user1);
        vm.stopPrank();

        uint256 rewardMergedRelic = IERC20(rewardToken1).balanceOf(user1);
        assertApproxEqAbs(
            rewardMergedRelic,
            5 ether + (10 ether * uint(200) / 320),
            1e5,
            "reward not expected"
        );
    }

    function testShift() public {
        rewardToken1.mint(address(rewardsPoolOHBR), 10 ether);
        rewardsPoolOHBR.fundRewarder();

        deal(address(poolToken), address(this), 100 ether);
        IERC20Metadata(address(poolToken)).approve(address(reliquary), type(uint).max);
        reliquary.createRelicAndDeposit(address(this), 0, 100 ether);

        address user1 = makeAddr("user1");
        deal(address(poolToken), user1, 200 ether);
        vm.startPrank(user1);
        IERC20Metadata(address(poolToken)).approve(address(reliquary), type(uint).max);
        reliquary.createRelicAndDeposit(user1, 0, 100 ether);
        vm.stopPrank();
        
        skip(7 days);
        reliquary.harvest(1, address(this));

        vm.startPrank(user1);
        reliquary.createRelicAndDeposit(user1, 0, 100 ether);
        reliquary.shift(2, 3, 100 ether);

        rewardToken1.mint(address(rewardsPoolOHBR), 10 ether);
        rewardsPoolOHBR.fundRewarder();

        skip(7 days);
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
