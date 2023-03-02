// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library ReliquaryEvents {
    event CreateRelic(uint indexed pid, address indexed to, uint indexed relicId);
    event Deposit(uint indexed pid, uint amount, address indexed to, uint indexed relicId);
    event Withdraw(uint indexed pid, uint amount, address indexed to, uint indexed relicId);
    event EmergencyWithdraw(uint indexed pid, uint amount, address indexed to, uint indexed relicId);
    event Harvest(uint indexed pid, uint amount, address indexed to, uint indexed relicId);
    event LogPoolAddition(
        uint indexed pid,
        uint allocPoint,
        address indexed poolToken,
        address indexed rewarder,
        address nftDescriptor,
        bool allowPartialWithdrawals
    );
    event LogPoolModified(uint indexed pid, uint allocPoint, address indexed rewarder, address nftDescriptor);
    event LogUpdatePool(uint indexed pid, uint lastRewardTime, uint lpSupply, uint accRewardPerShare);
    event LogSetEmissionCurve(address indexed emissionCurveAddress);
    event LevelChanged(uint indexed relicId, uint newLevel);
    event Split(uint indexed fromId, uint indexed toId, uint amount);
    event Shift(uint indexed fromId, uint indexed toId, uint amount);
    event Merge(uint indexed fromId, uint indexed toId, uint amount);
}
