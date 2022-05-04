// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./interfaces/IRewarder.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IReliquary.sol";

contract Rewarder is IRewarder {

    using SafeERC20 for IERC20;

    uint private constant BASIS_POINTS = 10_000;
    uint public immutable rewardMultiplier;
    IERC20 public immutable rewardToken;
    IReliquary public immutable reliquary;

    uint public immutable depositBonus;
    uint public immutable minimum;
    uint public immutable cadence;

    modifier onlyReliquary() {
        require(msg.sender == address(reliquary), "Only Reliquary can call this function.");
        _;
    }

    /// @param _rewardMultiplier Amount to multiply reward by, relative to BASIS_POINTS
    /// @param _depositBonus Bonus owed when enough time has elapsed since a term was created
    /// @param _minimum The minimum deposit amount to create a term
    /// @param _cadence The minimum elapsed time since last deposit or depositBonus claimed
    /// @param _rewardToken Address of token rewards are distributed in
    /// @param _reliquary Address of Reliquary this rewarder will read state from
    constructor(
        uint _rewardMultiplier,
        uint _depositBonus,
        uint _minimum,
        uint _cadence,
        IERC20 _rewardToken,
        IReliquary _reliquary
    ) {
        rewardMultiplier = _rewardMultiplier;
        depositBonus = _depositBonus;
        minimum = _minimum;
        cadence = _cadence;
        rewardToken = _rewardToken;
        reliquary = _reliquary;
    }

    mapping(uint => uint) public startTime;

    function onOathReward(
        uint relicId,
        address to,
        uint rewardAmount
    ) external override onlyReliquary {
        if (rewardMultiplier != 0) {
            uint pendingReward = rewardAmount * rewardMultiplier / BASIS_POINTS;
            uint rewardBal = rewardToken.balanceOf(address(this));
            if (pendingReward > rewardBal) {
                rewardToken.safeTransfer(to, rewardBal);
            } else {
                rewardToken.safeTransfer(to, pendingReward);
            }
        }
    }

    function onOathDeposit(
        uint relicId,
        address to,
        uint depositAmount
    ) external override onlyReliquary {
        if (depositAmount > minimum && block.timestamp - startTime[relicId] >= cadence) {
            _harvestRewards(relicId);
        }
    }

    function onOathWithdraw(
        uint relicId,
        address to,
        uint withdrawalAmount
    ) external override onlyReliquary {
        delete startTime[relicId];
    }

    function harvestRewards(uint relicId) external {
        require(block.timestamp - startTime[relicId] >= cadence);
        _harvestRewards(relicId);
    }

    function _harvestRewards(uint relicId) internal {
        startTime[relicId] = block.timestamp;
        rewardToken.safeTransfer(reliquary.ownerOf(relicId), depositBonus);
    }

    function pendingTokens(
        uint pid,
        address user,
        uint oathAmount
    ) external view override returns (IERC20[] memory rewardTokens, uint[] memory rewardAmounts) {
        rewardTokens = new IERC20[](1);
        rewardTokens[0] = rewardToken;
        rewardAmounts = new uint[](1);
        rewardAmounts[0] = oathAmount * rewardMultiplier / BASIS_POINTS;
    }
}
