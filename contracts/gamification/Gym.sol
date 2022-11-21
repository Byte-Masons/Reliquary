pragma solidity ^0.8.17;

import "./UseRandom.sol";
import "../interfaces/IReliquary.sol";

contract Gym is UseRandom {

    IReliquary public reliquary;
    mapping(uint => uint) seeds;

    constructor(IReliquary _reliquary) {
        reliquary = _reliquary;
    }

    /// @notice Assign same random seed to each Relic. May be called no more than once per day per Relic
    /// @param relicIds Array of relicIds belonging to msg.sender (may or may not be all of them)
    /// @return seed The seed used to generate a provably random number via VDF
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

    /// @notice Apply the maturity bonus derived from the seed assigned by createSeed function
    /// @param relicIds Array of relicIds which all have the same seed
    /// @param proof The provably random number derived from the VDF.
    ///        Used as number of seconds by which to reduce position's entry time.
    function train(uint[] calldata relicIds, uint proof) external {
        uint seed = seeds[relicIds[0]];
        require(seed != 0, "no seed");
        _prove(proof, seed);

        uint n = proof % 1 days;

        _train(relicIds[0], n);
        for (uint i = 1; i < relicIds.length;) {
            require(seeds[relicIds[i]] == seed, "Relic seed mismatch");
            _train(relicIds[i], n);
            unchecked {++i;}
        }
    }

    /// @notice Internal function which allows to apply effects to first relicId without redundant seed mismatch check
    /// @param relicId The NFT ID of the Relic being trained
    /// @param rand The provably random number derived from the VDF
    function _train(uint relicId, uint rand) internal {
        delete seeds[relicId];
        reliquary.modifyMaturity(relicId, rand);
    }
}
