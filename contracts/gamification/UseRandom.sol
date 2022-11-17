pragma solidity ^0.8.17;

import "../libraries/SlothVDF.sol";

abstract contract UseRandom {
    // large prime
    uint private constant PRIME = 432211379112113246928842014508850435796007;
    // adjust for block finality
    uint private constant ITERATIONS = 1000;
    // increment nonce to increase entropy
    uint private nonce;
    // vdf seeds
    uint[] public seeds;

    constructor() {
        seeds.push();
    }

    function _createSeed() internal returns (uint seed, uint index) {
        // commit funds/tokens/etc before running this function

        // create a pseudo random seed as the input
        index = ++nonce;
        seed = uint(keccak256(abi.encodePacked(msg.sender, index, block.timestamp, blockhash(block.number - 1))));
        seeds[index] = seed;
    }

    function _prove(uint proof, uint index) internal view {
        // see if the proof is valid for the seed associated with the address
        require(SlothVDF.verify(proof, seeds[index], PRIME, ITERATIONS), 'Invalid proof');

        // use the proof as a provable random number
    }
}
