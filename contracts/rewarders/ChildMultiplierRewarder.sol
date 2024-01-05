// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ChildRewarder.sol";
import "./MultiplierRewarder.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract ChildMultiplierRewarder is MultiplierRewarder, ChildRewarder, Ownable {

    constructor(
        uint _rewardMultiplier,
        address _rewardToken,
        address _reliquary
    ) MultiplierRewarder(_rewardMultiplier, _rewardToken, _reliquary) ChildRewarder() {}

    function onReward(
        uint relicId,
        uint rewardAmount,
        address to,
        uint, // oldAmount,
        uint, // oldLevel,
        uint // newLevel
    ) external override(IRewarder, MultiplierRewarder) onlyParent {
        _onReward(relicId, rewardAmount, to);
    }

}
