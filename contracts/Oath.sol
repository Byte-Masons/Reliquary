// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// TODO tess3rac7 why static import instead of npm?
// applies to all OZ/boring files everywhere
import "./OZ/token/ERC20/ERC20.sol";

// The token
contract Oath is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    // TODO tess3rac7 anyone can mint?
    function mint(address to, uint256 amount) external returns (bool) {
        _mint(to, amount);
        return true;
    }
}
