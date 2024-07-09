// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "contracts/Reliquary.sol";
import "contracts/nft_descriptors/NFTDescriptor.sol";
import "contracts/curves/LinearCurve.sol";
import "contracts/curves/LinearPlateauCurve.sol";
import "contracts/rewarders/RollingRewarder.sol";
import "contracts/rewarders/ParentRollingRewarder.sol";
import "openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";
import "./mocks/ERC20Mock.sol";
import "./mocks/VoterMock.sol";
import "./mocks/GaugeMock.sol";

contract MultipleRollingRewarder is ERC721Holder, Test {
    using Strings for address;
    using Strings for uint256;

    Reliquary public reliquary;
    LinearCurve public linearCurve;
    LinearPlateauCurve public linearPlateauCurve;
    ERC20Mock public oath;
    ERC20Mock public suppliedToken;
    ParentRollingRewarder public parentRewarder;
    
    address voter;
    address gaugeReceiver;

    uint256 public nbChildRewarder = 3;
    RollingRewarder[] public childRewarders;
    ERC20Mock[] public rewardTokens;

    address public nftDescriptor;

    //! here we set emission rate at 0 to simulate a pure collateral Ethos reward without any oath incentives.
    uint256 public emissionRate = 0;
    uint256 public initialMint = 100_000_000 ether;
    uint256 public initialDistributionPeriod = 7 days;

    // Linear function config (to config)
    uint256 public slope = 100; // Increase of multiplier every second
    uint256 public minMultiplier = 365 days * 100; // Arbitrary (but should be coherent with slope)
    uint256 public plateau = 100 days;
    
    address public gauge;

    function setUp() public {
        oath = new ERC20Mock(18);
        voter = address(new VoterMock());
        gaugeReceiver = makeAddr("gaugeReceiver");

        reliquary = new Reliquary(address(oath), emissionRate, gaugeReceiver, voter, "Reliquary Deposit", "RELIC");
        linearPlateauCurve = new LinearPlateauCurve(slope, minMultiplier, plateau);
        linearCurve = new LinearCurve(slope, minMultiplier);

        oath.mint(address(reliquary), initialMint);

        suppliedToken = new ERC20Mock(6);
        gauge = address(new GaugeMock(address(suppliedToken)));
        VoterMock(voter).setGauge(address(suppliedToken), gauge);

        nftDescriptor = address(new NFTDescriptor(address(reliquary)));

        parentRewarder = new ParentRollingRewarder();

        reliquary.grantRole(keccak256("OPERATOR"), address(this));

        deal(address(suppliedToken), address(this), 1);
        suppliedToken.approve(address(reliquary), 1); // approve 1 wei to bootstrap the pool
        reliquary.addPool(
            100,
            address(suppliedToken),
            address(parentRewarder),
            linearPlateauCurve,
            "ETH Pool",
            nftDescriptor,
            true,
            address(this)
        );

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            address rewardTokenTemp = address(new ERC20Mock(18));
            address rewarderTemp = parentRewarder.createChild(rewardTokenTemp);
            rewardTokens.push(ERC20Mock(rewardTokenTemp));
            childRewarders.push(RollingRewarder(rewarderTemp));
            ERC20Mock(rewardTokenTemp).mint(address(this), initialMint);
            ERC20Mock(rewardTokenTemp).approve(address(reliquary), type(uint256).max);
            ERC20Mock(rewardTokenTemp).approve(address(rewarderTemp), type(uint256).max);
        }

        suppliedToken.mint(address(this), initialMint);
        suppliedToken.approve(address(reliquary), type(uint256).max);
    }
    
    function testGaugeReward(uint256 rewardAmount) public {
        rewardAmount = bound(rewardAmount, 0, type(uint256).max / 2);
        uint256 amount = 1 ether;
        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, amount);
        skip(1 days);
        
        address[] memory gaugeRewardTokens = new address[](1);
        gaugeRewardTokens[0] = address(oath);
        uint256[] memory gaugeRewardAmounts = new uint256[](1);
        gaugeRewardAmounts[0] = rewardAmount;
        
        VoterMock(voter).setPendingRewards(gauge, gaugeRewardTokens, gaugeRewardAmounts);
        oath.mint(address(voter), rewardAmount);

        reliquary.update(relicId, address(this));
        reliquary.claimGaugeRewards(0, gaugeRewardTokens);
        assertEq(oath.balanceOf(gaugeReceiver), rewardAmount);
    }

    function testGaugeTransferRewardNotFullBalance(uint256 rewardAmount) public {
        rewardAmount = bound(rewardAmount, 0, type(uint256).max / 2);
        uint256 amount = 1 ether;
        uint256 relicId = reliquary.createRelicAndDeposit(address(this), 0, amount);
        skip(1 days);
        
        address[] memory gaugeRewardTokens = new address[](1);
        gaugeRewardTokens[0] = address(oath);
        uint256[] memory gaugeRewardAmounts = new uint256[](1);
        gaugeRewardAmounts[0] = rewardAmount;
        VoterMock(voter).setPendingRewards(gauge, gaugeRewardTokens, gaugeRewardAmounts);
        oath.mint(address(voter), rewardAmount);

        reliquary.update(relicId, address(this));
        uint256 balanceBefore = oath.balanceOf(address(reliquary));

        gaugeRewardTokens[0] = address(oath);
        reliquary.claimGaugeRewards(0, gaugeRewardTokens);
        
        assertEq(oath.balanceOf(gaugeReceiver), rewardAmount);
        assertEq(oath.balanceOf(address(reliquary)), balanceBefore);
    }
    
}
