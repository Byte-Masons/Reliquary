// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IReliquary.sol";

interface IVault is IERC20 {
  function deposit(uint256 _amount) external;
  function token() external returns (IERC20);
}

contract DepositHelper {

  using SafeERC20 for IERC20;

  IReliquary public reliquary;

  constructor(address _reliquary) {
    reliquary = IReliquary(_reliquary);
  }

  function deposit(
    uint pid,
    uint amount,
    uint relicId
  ) external {
    IVault vault = IVault(address(reliquary.lpToken(pid)));
    IERC20 token = vault.token();
    token.safeTransferFrom(msg.sender, address(this), amount);
    if (token.allowance(address(vault), address(this)) == 0) {
      token.safeApprove(address(vault), type(uint).max);
    }
    vault.deposit(amount);
    if (relicId == 0) {
      reliquary.createRelicAndDeposit(msg.sender, pid, vault.balanceOf(address(this)));
    } else {
      reliquary.deposit(vault.balanceOf(address(this)), relicId);
    }
  }

}
