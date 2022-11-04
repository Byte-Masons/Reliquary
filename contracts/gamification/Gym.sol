pragma solidity ^0.8.17;

import "./UseRandom.sol";
import "../interfaces/IReliquary.sol";
import "openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

interface IAvatar {
    // returns basis points
    function getBonus(uint id) external returns (uint);
}

contract Gym is UseRandom {
    struct Avatar {
        IAvatar collection;
        uint96 id;
    }

    uint private constant BASIS_POINTS = 10_000;

    IReliquary public reliquary;
    mapping(address => Avatar) public avatars;
    mapping(uint => bool) hasTrained;

    constructor(IReliquary _reliquary) {
        reliquary = _reliquary;
    }

    function createSeed(uint relicId) external returns (uint seed) {
        require(reliquary.isApprovedOrOwner(msg.sender, relicId), "not authorized");
        PositionInfo memory position = reliquary.getPositionForId(relicId);
        require(
            block.timestamp - position.genesis >= 1 days &&
            (position.lastMaturityBonus == 0 || block.timestamp - position.lastMaturityBonus >= 1 days),
            "too soon since last training"
        );

        delete hasTrained[relicId];
        seed = _createSeed();
        reliquary.updateLastMaturityBonus(relicId);
    }

    // might be possible with PRNG
    /*function multiTrain(uint[] calldata ids) external {
        for (uint i; i < ids.length; ++i) {
            train(ids[i]);
        }
    }*/

    function train(uint relicId, uint proof) public {
        require(reliquary.isApprovedOrOwner(msg.sender, relicId), "not authorized");
        require(!hasTrained[relicId], "seed already used");
        _prove(proof);
        hasTrained[relicId] = true;
        _train(relicId, proof);
    }

    function _train(uint relicId, uint rand) internal {
        uint n = rand % 1 days;
        Avatar memory avatar = avatars[msg.sender];
        if (avatar.id != 0) {
            n = n * avatar.collection.getBonus(avatar.id) / BASIS_POINTS;
        }
        reliquary.modifyMaturity(relicId, n);
    }
}
