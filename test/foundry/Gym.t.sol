// SPX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Reliquary.t.sol";
import "contracts/gamification/Gym.sol";

contract GymTest is ERC721Holder, Test {
    Gym gym;
    Reliquary reliquary;

    bytes32 constant MATURITY_MODIFIER = keccak256("MATURITY_MODIFIER");

    function setUp() public {
        vm.createSelectFork("fantom");
        ReliquaryTest reliquaryTest = new ReliquaryTest();
        reliquaryTest.setUp();

        reliquary = reliquaryTest.reliquary();
        TestToken testToken = reliquaryTest.testToken();

        testToken.mint(address(this), 100_000_000 ether);
        testToken.approve(address(reliquary), type(uint).max);

        gym = new Gym(reliquary);
        vm.prank(address(reliquaryTest));
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
