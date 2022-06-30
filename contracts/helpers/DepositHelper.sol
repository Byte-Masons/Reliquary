// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "../interfaces/IReliquary.sol";

interface IVault is IERC20 {
  function deposit(uint256 _amount) external;
  function withdraw(uint256 _amount) external;
  function getPricePerFullShare() external returns (uint);
  function token() external returns (IERC20);
}

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
  ) external pure returns (bytes4){
    return(IERC721Receiver.onERC721Received.selector);
  }

  function deposit(
    uint pid,
    uint amount,
    uint relicId
  ) external {
    IVault vault = IVault(address(reliquary.poolToken(pid)));
    IERC20 token = vault.token();
    token.safeTransferFrom(msg.sender, address(this), amount);
    if (token.allowance(address(vault), address(this)) == 0) {
      token.safeApprove(address(vault), type(uint).max);
    }
    vault.deposit(amount);
    if (relicId == 0) {
      reliquary.createRelicAndDeposit(msg.sender, pid, vault.balanceOf(address(this)));
    } else {
      IERC721 relic = IERC721(address(reliquary));
      relic.safeTransferFrom(msg.sender, address(this), relicId);
      reliquary.deposit(vault.balanceOf(address(this)), relicId);
      relic.safeTransferFrom(address(this), msg.sender, relicId);
    }
  }

  function withdraw(
    uint pid,
    uint amount,
    uint relicId
  ) external {
    IERC721 relic = IERC721(address(reliquary));
    IVault vault = IVault(address(reliquary.poolToken(pid)));
    IERC20 token = vault.token();

    uint amountInShares = amount * 1e18 / vault.getPricePerFullShare();
    relic.safeTransferFrom(msg.sender, address(this), relicId);
    reliquary.withdraw(amountInShares, relicId);

    vault.withdraw(vault.balanceOf(address(this)));
    token.transfer(msg.sender, token.balanceOf(address(this)));
    relic.safeTransferFrom(address(this), msg.sender, relicId);
  }

}
