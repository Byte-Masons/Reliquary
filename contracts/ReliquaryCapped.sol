// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Reliquary.sol";

/// @title Extension of Reliquary that allows the operator to set a total deposit cap per pool for testing purposes.
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
        uint pid = positionForId[relicId].poolId;
        if (amount + _poolBalanceBeforeMultipliers(pid) > depositCap[pid]) revert AmountExceedsCap();
        super.deposit(amount, relicId);
    }

    /// @inheritdoc Reliquary
    function createRelicAndDeposit(address to, uint pid, uint amount) public override returns (uint id) {
        if (amount + _poolBalanceBeforeMultipliers(pid) > depositCap[pid]) revert AmountExceedsCap();
        id = super.createRelicAndDeposit(to, pid, amount);
    }

    /**
     * @notice returns The total deposits of the pool's token, NOT weighted by maturity level allocation.
     * @param pid The index of the pool. See poolInfo.
     * @return total The amount of pool tokens held by the contract.
     */
    function _poolBalanceBeforeMultipliers(uint pid) internal view returns (uint total) {
        LevelInfo storage levelInfo = levels[pid];
        uint length = levelInfo.balance.length;
        for (uint i; i < length;) {
            total += levelInfo.balance[i];
            unchecked {
                ++i;
            }
        }
    }
}
