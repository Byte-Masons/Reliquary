// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "../interfaces/IReliquary.sol";

contract DepositHelper is IERC721Receiver {

  using SafeERC20 for IERC20;

  IReliquary public immutable reliquary;

  constructor(address _reliquary) {
    reliquary = IReliquary(_reliquary);
  }

  function onERC721Received(
    address operator,
    address from,
    uint256 tokenId,
    bytes calldata data
  ) external pure override returns (bytes4) {
    return(IERC721Receiver.onERC721Received.selector);
  }

  function deposit(
    uint pid,
    uint amount,
    uint relicId
  ) external {
    IERC4626 vault = IERC4626(address(reliquary.poolToken(pid)));
    IERC20 token = IERC20(vault.asset());
    token.safeTransferFrom(msg.sender, address(this), amount);

    if (token.allowance(address(this), address(vault)) == 0) {
      token.approve(address(vault), type(uint).max);
    }
    vault.deposit(amount, address(this));

    if (IERC20(vault).allowance(address(this), address(reliquary)) == 0) {
      IERC20(vault).approve(address(reliquary), type(uint).max);
    }
    if (relicId == 0) {
      reliquary.createRelicAndDeposit(msg.sender, pid, vault.balanceOf(address(this)));
    } else {
      reliquary.safeTransferFrom(msg.sender, address(this), relicId);
      reliquary.deposit(vault.balanceOf(address(this)), relicId);
      reliquary.safeTransferFrom(address(this), msg.sender, relicId);
    }
  }

  function withdraw(
    uint pid,
    uint amount,
    uint relicId
  ) external {
    IERC4626 vault = IERC4626(address(reliquary.poolToken(pid)));
    IERC20 token = IERC20(vault.asset());

    reliquary.safeTransferFrom(msg.sender, address(this), relicId);
    reliquary.withdraw(vault.convertToShares(amount), relicId);

    vault.maxWithdraw(address(this));
    token.transfer(msg.sender, token.balanceOf(address(this)));
    reliquary.safeTransferFrom(address(this), msg.sender, relicId);
  }

}
