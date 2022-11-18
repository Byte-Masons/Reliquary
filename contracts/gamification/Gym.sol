pragma solidity ^0.8.17;

import "./UseRandom.sol";
import "../interfaces/IReliquary.sol";

/*interface IAvatar {
    // returns basis points
    function getBonus(uint id) external returns (uint);
}*/

contract Gym is UseRandom {
    /*struct Avatar {
        IAvatar collection;
        uint96 id;
    }*/

    //uint private constant BASIS_POINTS = 10_000;

    IReliquary public reliquary;
    //mapping(address => Avatar) public avatars;
    mapping(uint => uint) seeds;

    constructor(IReliquary _reliquary) {
        reliquary = _reliquary;
    }

    function createSeed(uint[] calldata relicIds) external returns (uint seed) {
        seed = _createSeed();

        for (uint i; i < relicIds.length;) {
            require(reliquary.isApprovedOrOwner(msg.sender, relicIds[i]), "not authorized");
            PositionInfo memory position = reliquary.getPositionForId(relicIds[i]);
            require(
                block.timestamp - position.genesis >= 1 days &&
                (position.lastMaturityBonus == 0 || block.timestamp - position.lastMaturityBonus >= 1 days),
                "too soon since last bonus"
            );

            seeds[relicIds[i]] = seed;
            reliquary.updateLastMaturityBonus(relicIds[i]);
            unchecked {++i;}
        }
    }

    function train(uint[] calldata relicIds, uint proof) external {
        uint seed = seeds[relicIds[0]];
        require(seed != 0, "no seed");
        _prove(proof, seed);

        uint n = proof % 1 days;
        /*Avatar memory avatar = avatars[msg.sender];
        if (avatar.id != 0) {
            n = n * avatar.collection.getBonus(avatar.id) / BASIS_POINTS;
        }*/

        _train(relicIds[0], n);
        for (uint i = 1; i < relicIds.length;) {
            require(seeds[relicIds[i]] == seed, "Relic seed mismatch");
            _train(relicIds[i], n);
            unchecked {++i;}
        }
    }

    function _train(uint relicId, uint rand) internal {
        delete seeds[relicId];
        reliquary.modifyMaturity(relicId, rand);
    }
}
