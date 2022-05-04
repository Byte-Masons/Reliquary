// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./interfaces/IRewarder.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IReliquary.sol";

contract Rewarder is IRewarder {

    using SafeERC20 for IERC20;

    uint private constant BASIS_POINTS = 10_000;
    uint private immutable rewardMultiplier;
    IERC20 private immutable rewardToken;
    address private immutable RELIQUARY;

    uint public depositBonus;
    uint public minimum;
    uint public vestingTime;
    uint public cadence;

    constructor(
        uint _rewardMultiplier,
        uint _depositBonus,
        uint _minimum,
        uint _vestingTime,
        uint _cadence,
        IERC20 _rewardToken,
        address _reliquary
    ) {
        rewardMultiplier = _rewardMultiplier;
        depositBonus = _depositBonus;
        minimum = _minimum;
        vestingTime = _vestingTime;
        cadence = _cadence;
        rewardToken = _rewardToken;
        RELIQUARY = _reliquary;
    }

    mapping(uint => uint) public startTime;

    function harvestRewards(uint relicId) external {
        require(block.timestamp - startTime[relicId] >= cadence);
        _harvestRewards(relicId);
    }

    function onOathReward(
        uint relicId,
        address to,
        uint rewardAmount
    ) external override onlyReliquary {
        if (rewardMultiplier > 0) {
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
        if (depositAmount > minimum) {
            createTerms(relicId);
        }
    }

    function onOathWithdraw(
        uint relicId,
        address to,
        uint withdrawalAmount
    ) external override onlyReliquary {
        startTime[relicId] = 0;
    }

    function createTerms(uint relicId) internal {
        if (block.timestamp - startTime[relicId] < cadence) {
            return;
        } else {
            _harvestRewards(relicId);
            startTime[relicId] = block.timestamp;
        }
    }

    function _harvestRewards(uint relicId) internal {
        rewardToken.transfer(IReliquary(RELIQUARY).ownerOf(relicId), depositBonus);
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

    modifier onlyReliquary() {
        require(msg.sender == RELIQUARY, "Only Reliquary can call this function.");
        _;
    }
}
