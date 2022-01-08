pragma solidity ^0.8.0;

import "./OZ/token/ERC20/ERC20.sol";

contract Oath is ERC20 {

  constructor(string memory name, string memory symbol) ERC20(name, symbol) {

  }

  // anyone can mint?
  function mint(address to, uint amount) external returns (bool) {
    _mint(to, amount);
    return true;
  }

}
