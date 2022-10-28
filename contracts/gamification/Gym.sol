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

    constructor(IReliquary _reliquary) {
        reliquary = _reliquary;
    }

    /*function multiSpin(uint[] calldata ids) external {
        for (uint i; i < ids.length; ++i) {
            spin(ids[i]);
        }
    }*/

    function spin(uint relicId, uint proof) public {
        require(reliquary.isApprovedOrOwner(msg.sender, relicId), "not authorized");
        _prove(proof);
        _spin(relicId, proof);
    }

    function _spin(uint relicId, uint rand) internal {
        require(
            block.timestamp - reliquary.getPositionForId(relicId).lastMaturityBonus >= 1 days,
            "too soon since last spin"
        );

        uint n = rand % 1 days;
        Avatar memory ava = avatars[msg.sender];
        if (ava.id != 0) {
            n = n * ava.collection.getBonus(ava.id) / BASIS_POINTS;
        }
        //smarter rounding so it's an equal chance of hitting 24
        n = n / 1 hours * 1 hours;
        reliquary.modifyMaturity(relicId, n);
    }
}
