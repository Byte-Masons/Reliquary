// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Reliquary.sol";

/// @title Extension of Reliquary that allows the operator to set a deposit cap for testing purposes.
/// Only mitigates human error and is not gas-efficient.
contract ReliquaryCapped is Reliquary {
    /// @notice poolId => amount
    mapping(uint => uint) public depositCap;

    event LogSetDepositCap(uint indexed pid, uint amount);

    error AmountExceedsCap();

    constructor(address _rewardToken, address _emissionCurve) Reliquary(_rewardToken, _emissionCurve) {}

    function setDepositCap(uint pid, uint amount) external onlyRole(OPERATOR) {
        depositCap[pid] = amount;
        emit LogSetDepositCap(pid, amount);
    }

    /// @inheritdoc Reliquary
    function deposit(uint amount, uint relicId) public override {
        if (amount > depositCap[positionForId[relicId].poolId]) revert AmountExceedsCap();
        super.deposit(amount, relicId);
    }

    /// @inheritdoc Reliquary
    function createRelicAndDeposit(address to, uint pid, uint amount) public override returns (uint id) {
        if (amount > depositCap[pid]) revert AmountExceedsCap();
        id = super.createRelicAndDeposit(to, pid, amount);
    }

    /// @inheritdoc Reliquary
    function shift(uint fromId, uint toId, uint amount) public override {
        PositionInfo storage toPosition = positionForId[toId];
        if (amount + toPosition.amount > depositCap[toPosition.poolId]) revert AmountExceedsCap();
        super.shift(fromId, toId, amount);
    }

    /// @inheritdoc Reliquary
    function merge(uint fromId, uint toId) public override {
        PositionInfo storage toPosition = positionForId[toId];
        if (positionForId[fromId].amount + toPosition.amount > depositCap[toPosition.poolId]) revert AmountExceedsCap();
        super.merge(fromId, toId);
    }
}
