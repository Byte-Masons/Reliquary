// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// The token (test version)
contract TestToken is ERC20 {
    uint8 private immutable decimals_;

    constructor(string memory name, string memory symbol, uint8 _decimals) ERC20(name, symbol) {
        decimals_ = _decimals;
    }

    function mint(address to, uint amount) external returns (bool) {
        _mint(to, amount);
        return true;
    }

    function decimals() public view override returns (uint8) {
        return decimals_;
    }
}
