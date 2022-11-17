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
    mapping(uint => uint) seedIndex;

    constructor(IReliquary _reliquary) {
        reliquary = _reliquary;
    }

    function createSeed(uint[] calldata relicIds) external returns (uint) {
        (uint seed, uint index) = _createSeed();

        for (uint i; i < relicIds.length;) {
            require(reliquary.isApprovedOrOwner(msg.sender, relicIds[i]), "not authorized");
            PositionInfo memory position = reliquary.getPositionForId(relicIds[i]);
            require(
                block.timestamp - position.genesis >= 1 days &&
                (position.lastMaturityBonus == 0 || block.timestamp - position.lastMaturityBonus >= 1 days),
                "too soon since last bonus"
            );

            seedIndex[relicIds[i]] = index;
            reliquary.updateLastMaturityBonus(relicIds[i]);
            unchecked {++i;}
        }

        return seed;
    }

    function train(uint[] calldata relicIds, uint proof) public {
        uint index = seedIndex[relicIds[0]];
        require(index != 0, "no seed");
        _prove(proof, index);
        _train(relicIds[0], proof);

        for (uint i = 1; i < relicIds.length;) {
            require(seedIndex[relicIds[i]] == index, "Relic seed mismatch");
            _train(relicIds[i], proof);
            unchecked {++i;}
        }
    }

    function _train(uint relicId, uint rand) internal {
        require(reliquary.isApprovedOrOwner(msg.sender, relicId), "not authorized");

        delete seedIndex[relicId];

        uint n = rand % 1 days;
        /*Avatar memory avatar = avatars[msg.sender];
        if (avatar.id != 0) {
            n = n * avatar.collection.getBonus(avatar.id) / BASIS_POINTS;
        }*/
        reliquary.modifyMaturity(relicId, n);
    }
}
