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
        address[] storage poolToken,
        uint256 _pid
    ) public {
        PoolInfo storage pool = poolInfo[_pid];
        address gauge = address(pool.gaugeInfo.gauge);
        uint256 balance = IERC20(poolToken[_pid]).balanceOf(address(this));
        // Do nothing if this pool doesn't have a gauge
        if (pool.gaugeInfo.isGauge) {
            // Do nothing if the LP token in the MC is empty
            if (balance > 0) {
                // Approve to the gauge
                if (IERC20(poolToken[_pid]).allowance(address(this), gauge) < balance) {
                    IERC20(poolToken[_pid]).approve(gauge, type(uint256).max);
                }
                // Deposit the LP in the gauge
                pool.gaugeInfo.gauge.deposit(balance);
            }
        }
    }

    function withdrawFromGauge(
        PoolInfo[] storage poolInfo,
        uint256 _pid,
        uint256 _amount
    ) public {
        PoolInfo storage pool = poolInfo[_pid];
        // Do nothing if this pool doesn't have a gauge
        if (pool.gaugeInfo.isGauge) {
            // Withdraw from the gauge
            pool.gaugeInfo.gauge.withdraw(_amount);
        }
    }

    function enableGauge(
        IVoter voter,
        PoolInfo[] storage poolInfo,
        address[] storage poolToken,
        uint256 _pid
    ) public {
        address gauge = voter.gauges(address(poolToken[_pid]));
        if (gauge != address(0)) {
            poolInfo[_pid].gaugeInfo = GaugeInfo(true, IGauge(gauge));
            updatePoolWithGaugeDeposit(poolInfo, poolToken, _pid);
        }
    }

    function disableGauge(
        IVoter voter,
        PoolInfo[] storage poolInfo,
        address[] storage poolToken,
        uint256 _pid
    ) public {
        address gauge = voter.gauges(address(poolToken[_pid]));
        if (gauge != address(0)) {
            uint256 balance = IGauge(gauge).balanceOf(address(this));
            withdrawFromGauge(poolInfo, _pid, balance);
            poolInfo[_pid].gaugeInfo = GaugeInfo(false, IGauge(address(0)));
        }
    }

    function claimThenaRewards(PoolInfo[] storage poolInfo, address thenaToken, address thenaReceiver, uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.gaugeInfo.isGauge) {
            // claim the thena rewards
            pool.gaugeInfo.gauge.getReward(address(this));
            IERC20(thenaToken).safeTransfer(thenaReceiver, IERC20(thenaToken).balanceOf(address(this)));   
        }
    }
}
