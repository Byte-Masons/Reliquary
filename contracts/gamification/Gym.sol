pragma solidity ^0.8.17;

import "./UseRandom.sol";
import "../interfaces/IReliquary.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

interface IAvatar {
    // returns basis points
    function getBonus(uint id) external returns (uint);
}

contract Gym is UseRandom, Ownable {
    struct Avatar {
        IAvatar collection;
        uint96 id;
    }

    uint private constant BASIS_POINTS = 10_000;

    IReliquary public reliquary;
    mapping(address => Avatar) public avatars;
    mapping(uint => bool) hasSpun;

    constructor(IReliquary _reliquary) {
        reliquary = _reliquary;
    }

    function createSeed(uint relicId) external returns (uint seed) {
        require(reliquary.isApprovedOrOwner(msg.sender, relicId), "not authorized");
        PositionInfo memory position = reliquary.getPositionForId(relicId);
        require(
            block.timestamp - position.genesis >= 1 days &&
            (position.lastMaturityBonus == 0 || block.timestamp - position.lastMaturityBonus >= 1 days),
            "too soon since last spin"
        );

        reliquary.updateLastMaturityBonus(relicId);
        delete hasSpun[relicId];
        seed = _createSeed();
    }

    /*function multiSpin(uint[] calldata ids) external {
        for (uint i; i < ids.length; ++i) {
            spin(ids[i]);
        }
    }*/

    function spin(uint relicId, uint proof) public {
        require(reliquary.isApprovedOrOwner(msg.sender, relicId), "not authorized");
        require(!hasSpun[relicId], "seed already used");
        _prove(proof);
        hasSpun[relicId] = true;
        _spin(relicId, proof);
    }

    function _spin(uint relicId, uint rand) internal {
        uint n = rand % 1 days;
        Avatar memory ava = avatars[msg.sender];
        if (ava.id != 0) {
            n = n * ava.collection.getBonus(ava.id) / BASIS_POINTS;
        }
        reliquary.modifyMaturity(relicId, n);
    }
}
