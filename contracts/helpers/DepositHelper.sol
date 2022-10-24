// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import "../interfaces/IReliquary.sol";

contract DepositHelper {

  using SafeERC20 for IERC20;

  IReliquary public immutable reliquary;
  IERC20 public immutable rewardToken;

  constructor(IReliquary _reliquary) {
    reliquary = _reliquary;
    rewardToken = _reliquary.rewardToken();
  }

  function deposit(uint amount, uint relicId) external {
    IERC4626 vault = _prepareDeposit(reliquary.getPositionForId(relicId).poolId, amount);
    reliquary.deposit(vault.balanceOf(address(this)), relicId);
  }

  function createRelicAndDeposit(uint pid, uint amount) external returns (uint relicId) {
    IERC4626 vault = _prepareDeposit(pid, amount);
    relicId = reliquary.createRelicAndDeposit(msg.sender, pid, vault.balanceOf(address(this)));
  }

  function withdraw(uint amount, uint relicId, bool harvest) external {
    uint pid = reliquary.getPositionForId(relicId).poolId;
    IERC4626 vault = IERC4626(address(reliquary.poolToken(pid)));

    if (harvest) {
        reliquary.withdrawAndHarvest(vault.convertToShares(amount), relicId, msg.sender);
    } else {
        reliquary.withdraw(vault.convertToShares(amount), relicId);
    }

    vault.withdraw(vault.maxWithdraw(address(this)), msg.sender, address(this));
  }

  function _prepareDeposit(uint pid, uint amount) internal returns (IERC4626 vault) {
    vault = IERC4626(address(reliquary.poolToken(pid)));
    IERC20 token = IERC20(vault.asset());
    token.safeTransferFrom(msg.sender, address(this), amount);

    if (token.allowance(address(this), address(vault)) == 0) {
      token.approve(address(vault), type(uint).max);
    }
    vault.deposit(amount, address(this));

    if (vault.allowance(address(this), address(reliquary)) == 0) {
      vault.approve(address(reliquary), type(uint).max);
    }
  }

}
