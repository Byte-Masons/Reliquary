// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IVoter.sol";
import "../interfaces/IGauge.sol";
import "../interfaces/IReliquary.sol";

library DoubleStakingLogic {
    using SafeERC20 for IERC20;

    // @dev Deposit LP tokens to earn THE.
    function updatePoolWithGaugeDeposit(
        PoolInfo[] storage poolInfo,
        uint256 _pid
    ) public {
        PoolInfo memory pool = poolInfo[_pid];
        // Do nothing if this pool doesn't have a gauge
        if (pool.gauge != address(0)) {
            IERC20 poolToken = IERC20(pool.poolToken);
            uint256 balance = poolToken.balanceOf(address(this));
            // Do nothing if the LP token in the MC is empty
            if (balance > 0) {
                // Approve to the gauge
                if (poolToken.allowance(address(this), pool.gauge) < balance) {
                    poolToken.approve(pool.gauge, type(uint256).max);
                }
                // Deposit the LP in the gauge
                IGauge(pool.gauge).deposit(balance);
            }
        }
    }

    function withdrawFromGauge(
        PoolInfo[] storage poolInfo,
        uint256 _pid,
        uint256 _amount
    ) public {
        address gauge = poolInfo[_pid].gauge;
        // Do nothing if this pool doesn't have a gauge
        if (gauge != address(0)) {
            // Withdraw from the gauge
            IGauge(gauge).withdraw(_amount);
        }
    }

    function enableGauge(
        IVoter voter,
        PoolInfo[] storage poolInfo,
        uint256 _pid
    ) public {
        address gauge = voter.gauges(poolInfo[_pid].poolToken);
        if (gauge != address(0)) {
            poolInfo[_pid].gauge = gauge;
            updatePoolWithGaugeDeposit(poolInfo, _pid);
        }
    }

    function disableGauge(
        IVoter voter,
        PoolInfo[] storage poolInfo,
        uint256 _pid,
        address rewardReceiver,
        bool _claimRewards
    ) public {
        address gauge = voter.gauges(poolInfo[_pid].poolToken);
        if (gauge != address(0)) {
            uint256 balance = IGauge(gauge).balanceOf(address(this));
            withdrawFromGauge(poolInfo, _pid, balance);

            // claim rewards before disabling gauge 
            if (_claimRewards) {
                IGauge(gauge).getReward(address(this));
                IERC20 rewardToken = IERC20(IGauge(gauge).rewardToken());
                rewardToken.safeTransfer(rewardReceiver, rewardToken.balanceOf(address(this)));
            }

            // revoke allowance
            IERC20(poolInfo[_pid].poolToken).approve(gauge, 0);

            poolInfo[_pid].gauge = address(0);
        }
    }

    function claimGaugeRewards(
        IVoter voter,
        PoolInfo[] storage poolInfo,
        address rewardReceiver,
        uint256 _pid
    ) public {
        IGauge gauge = IGauge(poolInfo[_pid].gauge);
        if (address(gauge) != address(0)) {
            // claim the rewards
            address[] memory gauges = new address[](1);
            gauges[0] = poolInfo[_pid].gauge;
            voter.claimRewards(gauges);

            IERC20 rewardToken = IERC20(gauge.rewardToken());
            rewardToken.safeTransfer(rewardReceiver, rewardToken.balanceOf(address(this)));
        }
    }
}
