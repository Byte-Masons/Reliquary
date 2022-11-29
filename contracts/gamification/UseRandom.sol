// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../libraries/SlothVDF.sol";

abstract contract UseRandom {
    /// @dev Large prime.
    uint public constant PRIME = 432211379112113246928842014508850435796007;
    /// @dev Adjust for block finality.
    uint public constant ITERATIONS = 1000;
    /// @dev Increment nonce to increase entropy.
    uint private nonce;

    /// @dev Commit funds/tokens/etc before running this function. Creates a pseudo random seed as the input.
    function _createSeed() internal returns (uint seed) {
        seed = uint(keccak256(abi.encodePacked(msg.sender, ++nonce, block.timestamp, blockhash(block.number - 1))));
    }

    /// @dev Checks if the proof is valid for the seed associated with the address.
    /// `proof` may be used as a provable random number.
    function _prove(uint proof, uint seed) internal pure {
        require(SlothVDF.verify(proof, seed, PRIME, ITERATIONS), 'Invalid proof');
    }
}
