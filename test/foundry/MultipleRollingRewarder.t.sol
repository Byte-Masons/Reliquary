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

contract MultipleRollingRewarder is ERC721Holder, Test {
    using Strings for address;
    using Strings for uint256;

    Reliquary public reliquary;
    LinearCurve public linearCurve;
    LinearPlateauCurve public linearPlateauCurve;
    ERC20Mock public oath;
    ERC20Mock public suppliedToken;
    ParentRollingRewarder public parentRewarder;

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

    address public alice = address(0xA99);
    address public bob = address(0xB99);
    address public carlos = address(0xC99);

    address[] public users = [alice, bob, carlos];

    function setUp() public {
        oath = new ERC20Mock(18);

        reliquary = new Reliquary(address(oath), emissionRate, "Reliquary Deposit", "RELIC");
        linearPlateauCurve = new LinearPlateauCurve(slope, minMultiplier, plateau);
        linearCurve = new LinearCurve(slope, minMultiplier);

        oath.mint(address(reliquary), initialMint);

        suppliedToken = new ERC20Mock(6);

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

        // fund user
        for (uint256 u = 0; u < users.length; u++) {
            vm.startPrank(users[u]);
            suppliedToken.mint(users[u], initialMint);
            suppliedToken.approve(address(reliquary), type(uint256).max);
        }
    }

    function testMultiRewards1( /*uint256 seedInitialFunding*/ ) public {
        uint256 seedInitialFunding = 100000000000000000;
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
            reliquary.update(relics[u], users[u]);
            reliquary.withdraw(initialInvest, relics[u], address(0));
        }

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            for (uint256 u = 0; u < users.length; u++) {
                (, uint256[] memory rewardAmounts_) = parentRewarder.pendingTokens(relics[u]);
                assertEq(rewardAmounts_[i], 0); // 0,001%
                assertApproxEqRel(
                    rewardTokens[i].balanceOf(users[u]), initialFunding[i] / 3, 0.001e18
                ); // 0,001%
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
            reliquary.withdraw(initialInvest, relics[u], users[u]);
        }

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            for (uint256 u = 0; u < users.length; u++) {
                (, uint256[] memory rewardAmounts_) = parentRewarder.pendingTokens(relics[u]);
                assertEq(rewardAmounts_[i], 0); // 0,001%
                assertApproxEqRel(
                    rewardTokens[i].balanceOf(users[u]), initialFunding[i] * 2 / 3, 0.001e18
                ); // 0,001%
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
            reliquary.withdraw(initialInvest, relics[u], address(0));
            reliquary.update(relics[u], users[u]);
        }

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            for (uint256 u = 0; u < users.length; u++) {
                (, uint256[] memory rewardAmounts_) = parentRewarder.pendingTokens(relics[u]);
                assertEq(rewardAmounts_[i], 0); // 0,001%
                assertApproxEqRel(
                    rewardTokens[i].balanceOf(users[u]), initialFunding[i] / 3, 0.001e18
                ); // 0,001%
            }
        }
    }

    function testMultiRewardsUpdate(uint256 seedInitialFunding) public {
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

        skip(initialDistributionPeriod / 7);

        for (uint256 u = 0; u < users.length; u++) {
            vm.startPrank(users[u]);
            reliquary.update(relics[u], address(0));
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
            reliquary.withdraw(initialInvest, relics[u], users[u]);
        }

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            for (uint256 u = 0; u < users.length; u++) {
                (, uint256[] memory rewardAmounts_) = parentRewarder.pendingTokens(relics[u]);
                assertEq(rewardAmounts_[i], 0); // 0,001%
                assertApproxEqRel(
                    rewardTokens[i].balanceOf(users[u]), initialFunding[i] * 2 / 3, 0.001e18
                ); // 0,001%
            }
        }
    }

    function testMultiRewardsSplit(uint256 seedInitialFunding) public {
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

        skip(initialDistributionPeriod / 2);

        // split first relic
        vm.prank(users[0]);
        uint256 u0SlittedRelic = reliquary.split(relics[0], initialInvest / 2, users[0]);

        skip(initialDistributionPeriod / 2);

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            for (uint256 u = 1; u < users.length; u++) {
                (address[] memory rewardTokens_, uint256[] memory rewardAmounts_) =
                    parentRewarder.pendingTokens(relics[u]);
                assertApproxEqRel(rewardAmounts_[i], initialFunding[i] / 3, 0.001e18); // 0,001%
                assertEq(address(rewardTokens_[i]), address(rewardTokens[i]));
            }
        }

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            (, uint256[] memory rewardAmounts1_) = parentRewarder.pendingTokens(relics[0]);
            assertApproxEqRel(
                rewardAmounts1_[i],
                (
                    ((initialFunding[i] / 3) * (initialDistributionPeriod / 2))
                        + ((initialFunding[i] / 6) * (initialDistributionPeriod / 2))
                ) / initialDistributionPeriod,
                0.001e18
            ); // 0,001%

            (, uint256[] memory rewardAmounts2_) = parentRewarder.pendingTokens(u0SlittedRelic);
            assertApproxEqRel(
                rewardAmounts2_[i],
                (
                    (initialFunding[i] / 6) * (initialDistributionPeriod / 2)
                        / initialDistributionPeriod
                ),
                0.001e18
            ); // 0,001%
        }
        // withdraw
        for (uint256 u = 1; u < users.length; u++) {
            vm.startPrank(users[u]);
            reliquary.update(relics[u], users[u]);
            reliquary.withdraw(initialInvest, relics[u], address(0));
        }

        vm.startPrank(users[0]);

        reliquary.update(relics[0], users[0]);
        reliquary.withdraw(initialInvest / 2, relics[0], address(0));

        reliquary.update(u0SlittedRelic, users[0]);
        reliquary.withdraw(initialInvest / 2, u0SlittedRelic, address(0));

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            for (uint256 u = 0; u < users.length; u++) {
                (, uint256[] memory rewardAmounts_) = parentRewarder.pendingTokens(relics[u]);
                assertEq(rewardAmounts_[i], 0); // 0,001%
                assertApproxEqRel(
                    rewardTokens[i].balanceOf(users[u]), initialFunding[i] / 3, 0.001e18
                ); // 0,001%
            }
        }
    }

    function testMultiRewardsShift(uint256 seedInitialFunding) public {
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

        skip(initialDistributionPeriod / 2);

        // shift first relic into the second one
        vm.prank(users[1]);
        reliquary.approve(users[0], relics[1]);
        vm.prank(users[0]);
        reliquary.shift(relics[0], relics[1], initialInvest / 2);

        skip(initialDistributionPeriod / 2);

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            for (uint256 u = 2; u < users.length; u++) {
                (address[] memory rewardTokens_, uint256[] memory rewardAmounts_) =
                    parentRewarder.pendingTokens(relics[u]);
                assertApproxEqRel(rewardAmounts_[i], initialFunding[i] / 3, 0.005e18); // 0,001%
                assertEq(address(rewardTokens_[i]), address(rewardTokens[i]));
            }
        }

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            (, uint256[] memory rewardAmounts1_) = parentRewarder.pendingTokens(relics[0]);
            assertApproxEqRel(
                rewardAmounts1_[i],
                (
                    ((initialFunding[i] / 3) * (initialDistributionPeriod / 2))
                        + ((initialFunding[i] / 6) * (initialDistributionPeriod / 2))
                ) / initialDistributionPeriod,
                0.005e18
            ); // 0,005%

            // (, uint256[] memory rewardAmounts2_) = parentRewarder.pendingTokens(relics[1]);
            // assertApproxEqRel(
            //     rewardAmounts2_[i],
            //     (
            //         ((initialFunding[i] / 3) * (initialDistributionPeriod / 2))
            //             + ((initialFunding[i]  * 2/ 3) * (initialDistributionPeriod / 2))
            //     ) / initialDistributionPeriod,
            //     0.001e18
            // ); // 0,001%
        }
        // withdraw
        for (uint256 u = 2; u < users.length; u++) {
            vm.startPrank(users[u]);
            reliquary.update(relics[u], users[u]);
            reliquary.withdraw(initialInvest, relics[u], address(0));
        }

        vm.startPrank(users[0]);
        reliquary.update(relics[0], users[0]);
        reliquary.withdraw(initialInvest / 2, relics[0], address(0));

        vm.startPrank(users[1]);
        reliquary.update(relics[1], users[1]);
        reliquary.withdraw(initialInvest + initialInvest / 2, relics[1], address(0));

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            for (uint256 u = 2; u < users.length; u++) {
                (, uint256[] memory rewardAmounts_) = parentRewarder.pendingTokens(relics[u]);
                assertEq(rewardAmounts_[i], 0);
                assertApproxEqRel(
                    rewardTokens[i].balanceOf(users[u]), initialFunding[i] / 3, 0.005e18
                ); // 0,005%
            }
        }
        for (uint256 i = 0; i < nbChildRewarder; i++) {
            (, uint256[] memory rewardAmounts1_) = parentRewarder.pendingTokens(relics[0]);
            assertEq(rewardAmounts1_[i], 0);
            assertApproxEqRel(
                rewardTokens[i].balanceOf(users[0]),
                (
                    ((initialFunding[i] / 3) * (initialDistributionPeriod / 2))
                        + ((initialFunding[i] / 6) * (initialDistributionPeriod / 2))
                ) / initialDistributionPeriod,
                0.005e18
            ); // 0,005%

            (, uint256[] memory rewardAmounts2_) = parentRewarder.pendingTokens(relics[1]);
            assertEq(rewardAmounts2_[i], 0); // 0,001%
                // assertApproxEqRel(
                //     rewardTokens[i].balanceOf(users[1]),
                //     (
                //         ((initialFunding[i] / 3) * (initialDistributionPeriod / 2))
                //             + ((initialFunding[i]  * 2/ 3) * (initialDistributionPeriod / 2))
                //     ) / initialDistributionPeriod,
                //     0.005e18
                // ); // 0,005%
        }
    }

    function testMultiRewardsMerge(uint256 seedInitialFunding) public {
        // uint256 seedInitialFunding = 100000000000000000;

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

        skip(initialDistributionPeriod / 2);

        // shift first relic into the second one
        vm.prank(users[1]);
        reliquary.approve(users[0], relics[1]);
        vm.prank(users[0]);
        reliquary.merge(relics[0], relics[1]);

        skip(initialDistributionPeriod / 2);

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            for (uint256 u = 2; u < users.length; u++) {
                (address[] memory rewardTokens_, uint256[] memory rewardAmounts_) =
                    parentRewarder.pendingTokens(relics[u]);
                assertApproxEqRel(rewardAmounts_[i], initialFunding[i] / 3, 0.005e18); // 0,001%
                assertEq(address(rewardTokens_[i]), address(rewardTokens[i]));
            }
        }

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            (, uint256[] memory rewardAmounts1_) = parentRewarder.pendingTokens(relics[0]);
            assertEq(rewardAmounts1_[i], 0);

            (, uint256[] memory rewardAmounts2_) = parentRewarder.pendingTokens(relics[1]);
            assertApproxEqRel(rewardAmounts2_[i], initialFunding[i] * 2 / 3, 0.005e18); // 0,005%
        }
        // withdraw
        for (uint256 u = 2; u < users.length; u++) {
            vm.startPrank(users[u]);
            reliquary.update(relics[u], users[u]);
            reliquary.withdraw(initialInvest, relics[u], address(0));
        }

        vm.startPrank(users[1]);
        reliquary.update(relics[1], users[1]);
        reliquary.withdraw(initialInvest * 2, relics[1], address(0));

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            for (uint256 u = 2; u < users.length; u++) {
                (, uint256[] memory rewardAmounts_) = parentRewarder.pendingTokens(relics[u]);
                assertEq(rewardAmounts_[i], 0);
                assertApproxEqRel(
                    rewardTokens[i].balanceOf(users[u]), initialFunding[i] / 3, 0.005e18
                ); // 0,005%
            }
        }

        for (uint256 i = 0; i < nbChildRewarder; i++) {
            (, uint256[] memory rewardAmounts1_) = parentRewarder.pendingTokens(relics[0]);
            assertEq(rewardAmounts1_[i], 0);

            assertEq(rewardTokens[i].balanceOf(users[0]), 0);

            (, uint256[] memory rewardAmounts2_) = parentRewarder.pendingTokens(relics[1]);
            assertEq(rewardAmounts2_[i], 0); // 0,001%
            assertApproxEqRel(
                rewardTokens[i].balanceOf(users[1]), initialFunding[i] * 2 / 3, 0.005e18
            ); // 0,005%
        }
    }
}
