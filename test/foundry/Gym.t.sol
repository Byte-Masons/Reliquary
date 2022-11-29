// SPX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "contracts/gamification/Gym.sol";
import "contracts/ReliquaryGamified.sol";
import "contracts/emission_curves/Constant.sol";
import "contracts/nft_descriptors/NFTDescriptor.sol";
import "contracts/test/TestToken.sol";
import "openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";

contract GymTest is ERC721Holder, Test {
    Gym gym;
    ReliquaryGamified reliquary;

    bytes32 constant MATURITY_MODIFIER = keccak256("MATURITY_MODIFIER");

    uint[] requiredMaturity = [0, 1 days, 7 days, 14 days, 30 days, 90 days, 180 days, 365 days];
    uint[] allocPoints = [100, 120, 150, 200, 300, 400, 500, 750];

    function setUp() public {
        vm.createSelectFork("fantom");

        TestToken oath = new TestToken("Oath Token", "OATH", 18);
        IEmissionCurve curve = IEmissionCurve(address(new Constant()));

        reliquary = new ReliquaryGamified(oath, curve);

        TestToken testToken = new TestToken("Test Token", "TT", 6);
        testToken.mint(address(this), 100_000_000 ether);
        testToken.approve(address(reliquary), type(uint).max);

        INFTDescriptor nftDescriptor = INFTDescriptor(address(new NFTDescriptor(IReliquary(address(reliquary)))));

        reliquary.grantRole(keccak256("OPERATOR"), address(this));
        reliquary.addPool(
            100, testToken, IRewarder(address(0)), requiredMaturity, allocPoints, "ETH Pool", nftDescriptor
        );

        gym = new Gym(reliquary);
        reliquary.grantRole(MATURITY_MODIFIER, address(gym));
    }

    function testTrain() public {
        uint relicId = reliquary.createRelicAndDeposit(address(this), 0, 1 ether);
        uint[] memory relicIds = new uint[](1);
        relicIds[0] = relicId;

        vm.expectRevert(bytes("too soon since last bonus"));
        gym.createSeed(relicIds);

        skip(1 days);
        uint seed = gym.createSeed(relicIds);

        uint proof = SlothVDF.compute(seed, gym.PRIME(), gym.ITERATIONS());
        console2.log("Gym random number: ", proof);

        PositionInfo memory position = reliquary.getPositionForId(relicId);
        uint entry1 = position.entry;
        console2.log("entry before: ", entry1);

        gym.train(relicIds, proof);

        position = reliquary.getPositionForId(relicId);
        uint entry2 = position.entry;
        console2.log("entry after: ", entry2);
        uint difference = entry1 - entry2;
        console2.log("difference: ", entry1 - entry2);

        assertTrue(difference <= 1 days);
    }
}
