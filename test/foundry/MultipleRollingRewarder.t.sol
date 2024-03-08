// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "contracts/Reliquary.sol";
import "contracts/nft_descriptors/NFTDescriptor.sol";
import "contracts/curves/LinearCurve.sol";
import "contracts/curves/LinearPlateauCurve.sol";
import "contracts/rewarders/RollingRewarder.sol";
import "contracts/rewarders/ParentRollingRewarder.sol";
import "openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";
import "openzeppelin-contracts/contracts/mocks/ERC20DecimalsMock.sol";

contract MultipleRollingRewarder is ERC721Holder, Test {
    using Strings for address;
    using Strings for uint256;

    Reliquary public reliquary;
    LinearCurve public linearCurve;
    LinearPlateauCurve public linearPlateauCurve;
    ERC20DecimalsMock public oath;
    ERC20DecimalsMock public suppliedToken;
    ParentRollingRewarder public parentRewarder;

    uint256 public nbChildRewarder = 1;
    RollingRewarder[] public childRewarders;
    ERC20DecimalsMock[] public rewardTokens;

    address public nftDescriptor;

    //! here we set emission rate at 0 to simulate a pure collateral Ethos reward without any oath incentives.
    uint256 public emissionRate = 0;
    uint256 public initialMint = 100_000_000 ether;
    uint256 public initialDistributionPeriod = 7 days;

    // Linear function config (to config)
    uint256 public slope = 100; // Increase of multiplier every second
    uint256 public minMultiplier = 365 days * 100; // Arbitrary (but should be coherent with slope)
    uint256 public plateau = 100 days;

    address public alice = address(0xA99);
    address public bob = address(0xB99);
    address public carlos = address(0xC99);

    address[] public users = [alice, bob, carlos];

    function setUp() public {
        oath = new ERC20DecimalsMock("Oath Token", "OATH", 18);

        reliquary = new Reliquary(address(oath), emissionRate, "Reliquary Deposit", "RELIC");
        linearPlateauCurve = new LinearPlateauCurve(slope, minMultiplier, plateau);
        linearCurve = new LinearCurve(slope, minMultiplier);

        oath.mint(address(reliquary), initialMint);

        suppliedToken = new ERC20DecimalsMock("Test Token", "TT", 6);

        nftDescriptor = address(new NFTDescriptor(address(reliquary)));

        parentRewarder = new ParentRollingRewarder();

        reliquary.grantRole(keccak256("OPERATOR"), address(this));

        reliquary.addPool(
            100,
            address(suppliedToken),
            address(parentRewarder),
            linearPlateauCurve,
            "ETH Pool",
            nftDescriptor,
            true
        );

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            address rewardTokenTemp = address(new ERC20DecimalsMock("RT1", "RT1", 18));
            address rewarderTemp = parentRewarder.createChild(rewardTokenTemp);
            rewardTokens.push(ERC20DecimalsMock(rewardTokenTemp));
            childRewarders.push(RollingRewarder(rewarderTemp));
            ERC20DecimalsMock(rewardTokenTemp).mint(address(this), initialMint);
            ERC20DecimalsMock(rewardTokenTemp).approve(address(reliquary), type(uint256).max);
            ERC20DecimalsMock(rewardTokenTemp).approve(address(rewarderTemp), type(uint256).max);
        }

        suppliedToken.mint(address(this), initialMint);
        suppliedToken.approve(address(reliquary), type(uint256).max);

        // fund user
        for (uint256 u = 0; u < users.length; u++) {
            vm.startPrank(users[u]);
            suppliedToken.mint(users[u], initialMint);
            suppliedToken.approve(address(reliquary), type(uint256).max);
        }
    }

    function testMultiRewards1(uint256 seedInitialFunding) public {
        // uint seedInitialFunding = 100000000000000000;
        uint256[] memory initialFunding = new uint256[](nbChildRewarder);
        for (uint256 i = 0; i < nbChildRewarder; i++) {
            initialFunding[i] = bound(seedInitialFunding / (i + 1), 100000, initialMint);
        }

        uint256 initialInvest = 100 ether;
        uint256[] memory relics = new uint256[](users.length);
        for (uint256 u = 0; u < users.length; u++) {
            vm.startPrank(users[u]);
            relics[u] = reliquary.createRelicAndDeposit(users[u], 0, initialInvest);
        }
        vm.stopPrank();

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            childRewarders[i].fund(initialFunding[i]);
        }

        skip(initialDistributionPeriod);

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            for (uint256 u = 0; u < users.length; u++) {
                (address[] memory rewardTokens_, uint256[] memory rewardAmounts_) =
                    parentRewarder.pendingTokens(relics[u]);
                assertApproxEqRel(rewardAmounts_[i], initialFunding[i] / 3, 0.001e18); // 0,001%
                assertEq(address(rewardTokens_[i]), address(rewardTokens[i]));
            }
        }

        // withdraw
        for (uint256 u = 0; u < users.length; u++) {
            vm.startPrank(users[u]);
            reliquary.harvest(relics[u], users[u]);
            reliquary.withdraw(initialInvest, relics[u]);
        }

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            for (uint256 u = 0; u < users.length; u++) {
                (, uint256[] memory rewardAmounts_) = parentRewarder.pendingTokens(relics[u]);
                assertEq(rewardAmounts_[i], 0); // 0,001%
                assertApproxEqRel(rewardTokens[i].balanceOf(users[u]), initialFunding[i] / 3, 0.001e18); // 0,001%
            }
        }
    }

    function testMultiRewards2(uint256 seedInitialFunding) public {
        uint256[] memory initialFunding = new uint256[](nbChildRewarder);
        for (uint256 i = 0; i < nbChildRewarder; i++) {
            initialFunding[i] = bound(seedInitialFunding / (i + 1), 100000, initialMint / 2);
        }

        uint256 initialInvest = 100 ether;
        uint256[] memory relics = new uint256[](users.length);
        for (uint256 u = 0; u < users.length; u++) {
            vm.startPrank(users[u]);
            relics[u] = reliquary.createRelicAndDeposit(users[u], 0, initialInvest);
        }
        vm.stopPrank();

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            childRewarders[i].fund(initialFunding[i]);
        }

        skip(initialDistributionPeriod / 2);

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            childRewarders[i].fund(initialFunding[i]);
        }

        skip(initialDistributionPeriod);

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            for (uint256 u = 0; u < users.length; u++) {
                (address[] memory rewardTokens_, uint256[] memory rewardAmounts_) =
                    parentRewarder.pendingTokens(relics[u]);
                assertApproxEqRel(rewardAmounts_[i], initialFunding[i] * 2 / 3, 0.001e18); // 0,001%
                assertEq(address(rewardTokens_[i]), address(rewardTokens[i]));
            }
        }

        // withdraw
        for (uint256 u = 0; u < users.length; u++) {
            vm.startPrank(users[u]);
            reliquary.withdrawAndHarvest(initialInvest, relics[u], users[u]);
        }

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            for (uint256 u = 0; u < users.length; u++) {
                (, uint256[] memory rewardAmounts_) = parentRewarder.pendingTokens(relics[u]);
                assertEq(rewardAmounts_[i], 0); // 0,001%
                assertApproxEqRel(rewardTokens[i].balanceOf(users[u]), initialFunding[i] * 2 / 3, 0.001e18); // 0,001%
            }
        }
    }

    function testMultiRewards3(uint256 seedInitialFunding) public {
        uint256[] memory initialFunding = new uint256[](nbChildRewarder);
        for (uint256 i = 0; i < nbChildRewarder; i++) {
            initialFunding[i] = bound(seedInitialFunding / (i + 1), 100000, initialMint / 2);
        }

        uint256 initialInvest = 100 ether;
        uint256[] memory relics = new uint256[](users.length);
        for (uint256 u = 0; u < users.length; u++) {
            vm.startPrank(users[u]);
            relics[u] = reliquary.createRelicAndDeposit(users[u], 0, initialInvest);
        }
        vm.stopPrank();

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            childRewarders[i].fund(initialFunding[i]);
        }

        skip(initialDistributionPeriod / 2);

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            childRewarders[i].fund(initialFunding[i]);
        }

        skip(initialDistributionPeriod / 2);

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            for (uint256 u = 0; u < users.length; u++) {
                (address[] memory rewardTokens_, uint256[] memory rewardAmounts_) =
                    parentRewarder.pendingTokens(relics[u]);
                assertApproxEqRel(rewardAmounts_[i], initialFunding[i] / 3, 0.001e18); // 0,001%
                assertEq(address(rewardTokens_[i]), address(rewardTokens[i]));
            }
        }

        // withdraw
        for (uint256 u = 0; u < users.length; u++) {
            vm.startPrank(users[u]);
            reliquary.withdraw(initialInvest, relics[u]);
            reliquary.harvest(relics[u], users[u]);
        }

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            for (uint256 u = 0; u < users.length; u++) {
                (, uint256[] memory rewardAmounts_) = parentRewarder.pendingTokens(relics[u]);
                assertEq(rewardAmounts_[i], 0); // 0,001%
                assertApproxEqRel(rewardTokens[i].balanceOf(users[u]), initialFunding[i] / 3, 0.001e18); // 0,001%
            }
        }
    }
}
