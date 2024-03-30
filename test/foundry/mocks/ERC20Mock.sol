// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "openzeppelin-contracts/contracts/mocks/token/ERC20DecimalsMock.sol";

contract ERC20Mock is ERC20DecimalsMock {
    constructor(uint8 _dec) ERC20("ERC20Mock", "E20M") ERC20DecimalsMock(_dec) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}
