// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Reliquary.sol";
import "./interfaces/IReliquaryGamified.sol";

contract ReliquaryGamified is Reliquary, IReliquaryGamified {
    bytes32 private constant MATURITY_MODIFIER = keccak256("MATURITY_MODIFIER");

    /// @notice relicId => timestamp of Relic creation
    mapping(uint => uint) public genesis;
    /// @notice relicId => timestamp of last committed maturity bonus
    mapping(uint => uint) public lastMaturityBonus;

    event MaturityBonus(
        uint indexed pid,
        address indexed to,
        uint indexed relicId,
        uint bonus
    );

    constructor(IERC20 _rewardToken, IEmissionCurve _emissionCurve) Reliquary(_rewardToken, _emissionCurve) {}

    /*
     + @notice Allows an address with the MATURITY_MODIFIER role to modify a position's maturity within set limits.
     + @param relicId The NFT ID of the position being modified.
     + @param points Number of seconds to reduce the position's entry by (increasing maturity), before maximum.
     + @return receivedBonus Actual maturity bonus received after maximum.
    */
    function modifyMaturity(
        uint relicId,
        uint points
    ) external override onlyRole(MATURITY_MODIFIER) returns (uint receivedBonus) {
        receivedBonus = Math.min(1 days, points);
        PositionInfo storage position = positionForId[relicId];
        position.entry -= receivedBonus;
        _updatePosition(0, relicId, Kind.OTHER, address(0));

        emit MaturityBonus(position.poolId, ownerOf(relicId), relicId, receivedBonus);
    }

    function commitLastMaturityBonus(uint relicId) external override onlyRole(MATURITY_MODIFIER) {
        lastMaturityBonus[relicId] = block.timestamp;
    }

    /*
     + @notice Create a new Relic NFT and deposit into this position
     + @param to Address to mint the Relic to
     + @param pid The index of the pool. See `poolInfo`.
     + @param amount Token amount to deposit.
    */
    function createRelicAndDeposit(
        address to,
        uint pid,
        uint amount
    ) public override (IReliquary, Reliquary) returns (uint id) {
        id = super.createRelicAndDeposit(to, pid, amount);
        genesis[id] = block.timestamp;
    }

    /// @notice Split an owned Relic into a new one, while maintaining maturity
    /// @param fromId The NFT ID of the Relic to split from
    /// @param amount Amount to move from existing Relic into the new one
    /// @param to Address to mint the Relic to
    /// @return newId The NFT ID of the new Relic
    function split(uint fromId, uint amount, address to) public override (IReliquary, Reliquary) returns (uint newId) {
        newId = super.split(fromId, amount, to);
        genesis[newId] = block.timestamp;
    }

    /// @notice Transfer amount from one Relic into another, updating maturity in the receiving Relic
    /// @param fromId The NFT ID of the Relic to transfer from
    /// @param toId The NFT ID of the Relic being transferred to
    /// @param amount The amount being transferred
    function shift(uint fromId, uint toId, uint amount) public override (IReliquary, Reliquary) {
        super.shift(fromId, toId, amount);
        lastMaturityBonus[toId] = Math.max(lastMaturityBonus[fromId], lastMaturityBonus[toId]);
    }

    /// @notice Transfer entire position (including rewards) from one Relic into another, burning it
    /// and updating maturity in the receiving Relic
    /// @param fromId The NFT ID of the Relic to transfer from
    /// @param toId The NFT ID of the Relic being transferred to
    function merge(uint fromId, uint toId) public override (IReliquary, Reliquary) {
        super.merge(fromId, toId);
        lastMaturityBonus[toId] = Math.max(lastMaturityBonus[fromId], lastMaturityBonus[toId]);
    }

    function burn(uint tokenId) public override (IReliquary, Reliquary) {
        super.burn(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override (IReliquary, Reliquary) returns (bool) {
        return interfaceId == type(IReliquaryGamified).interfaceId || super.supportsInterface(interfaceId);
    }
}
