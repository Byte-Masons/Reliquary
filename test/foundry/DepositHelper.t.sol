// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "contracts/helpers/DepositHelper.sol";

contract DepositHelperTest is Test {
    DepositHelper helper;
    IERC20 weth;
    address constant WETH_WHALE = 0x2400BB4D7221bA530Daee061D5Afe219E9223Eae;

    function setUp() public {
        helper = new DepositHelper(0x90fEC9587624dC4437833Ef3C34C218996B8AB98);
        weth = IERC20(IERC4626(address(helper.reliquary().poolToken(0))).asset());

        vm.startPrank(address(WETH_WHALE), address(WETH_WHALE));
        weth.approve(address(helper), type(uint).max);
    }

    function testCreateNew() public {
        helper.deposit(0, 1e18, 0);
    }

    function testDepositExisting() public {
        helper.deposit(0, 1e18, 0);
        helper.reliquary().setApprovalForAll(address(helper), true);

        helper.deposit(0, 5e17, helper.reliquary().tokenOfOwnerByIndex(WETH_WHALE, 0));
    }

    function testWithdraw() public {
        helper.deposit(0, 1e18, 0);
        helper.reliquary().setApprovalForAll(address(helper), true);

        uint initialBalance = weth.balanceOf(WETH_WHALE);
        helper.withdraw(0, 1e18, helper.reliquary().tokenOfOwnerByIndex(WETH_WHALE, 0));
        uint diff = weth.balanceOf(WETH_WHALE) - initialBalance;

        assertTrue(diff == 0);
    }
}
