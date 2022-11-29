// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../libraries/SlothVDF.sol";

abstract contract UseRandom {
    // large prime
    uint public constant PRIME = 432211379112113246928842014508850435796007;
    // adjust for block finality
    uint public constant ITERATIONS = 1000;
    // increment nonce to increase entropy
    uint private nonce;

    function _createSeed() internal returns (uint seed) {
        // commit funds/tokens/etc before running this function

        // create a pseudo random seed as the input
        seed = uint(keccak256(abi.encodePacked(msg.sender, ++nonce, block.timestamp, blockhash(block.number - 1))));
    }

    function _prove(uint proof, uint seed) internal pure {
        // see if the proof is valid for the seed associated with the address
        require(SlothVDF.verify(proof, seed, PRIME, ITERATIONS), 'Invalid proof');

        // use the proof as a provable random number
    }
}
