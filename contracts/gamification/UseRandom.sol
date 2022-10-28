pragma solidity ^0.8.17;

import "../libraries/SlothVDF.sol";

abstract contract UseRandom {
    // large prime
    uint public constant PRIME = 432211379112113246928842014508850435796007;
    // adjust for block finality
    uint public constant ITERATIONS = 1000;
    // increment nonce to increase entropy
    uint private nonce;
    // address -> vdf seed
    mapping(address => uint) public seeds;

    function createSeed() external {
        // commit funds/tokens/etc here?

        // create a pseudo random seed as the input
        seeds[msg.sender] = uint(keccak256(abi.encodePacked(msg.sender, nonce++, block.timestamp, blockhash(block.number - 1))));
    }

    function _prove(uint proof) internal view {
        // see if the proof is valid for the seed associated with the address
        require(SlothVDF.verify(proof, seeds[msg.sender], PRIME, ITERATIONS), 'Invalid proof');

        // use the proof as a provable random number
    }
}
