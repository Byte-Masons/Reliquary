// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

library ReliquaryEvents {
    event CreateRelic(uint8 indexed pid, address indexed to, uint256 indexed relicId);
    event Deposit(uint8 indexed pid, uint256 amount, address indexed to, uint256 indexed relicId);
    event Withdraw(uint8 indexed pid, uint256 amount, address indexed to, uint256 indexed relicId);
    event Harvest(uint8 indexed pid, uint256 amount, address indexed to, uint256 indexed relicId);
    event Update(uint8 indexed pid, uint256 indexed relicId);

    event EmergencyWithdraw(
        uint8 indexed pid, uint256 amount, address indexed to, uint256 indexed relicId
    );
    event LogPoolAddition(
        uint8 indexed pid,
        uint256 allocPoint,
        address indexed poolToken,
        address indexed rewarder,
        address nftDescriptor,
        bool allowPartialWithdrawals
    );
    event LogPoolModified(
        uint8 indexed pid, uint256 allocPoint, address indexed rewarder, address nftDescriptor
    );
    event LogSetEmissionRate(uint256 indexed emissionRate);
    event Split(uint256 indexed fromId, uint256 indexed toId, uint256 amount);
    event Shift(uint256 indexed fromId, uint256 indexed toId, uint256 amount);
    event Merge(uint256 indexed fromId, uint256 indexed toId, uint256 amount);
}
