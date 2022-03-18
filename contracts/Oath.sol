// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// The token (test version)
contract Oath is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    // anyone can mint(!) since it's test version
    function mint(address to, uint256 amount) external returns (bool) {
        _mint(to, amount);
        return true;
    }
}
