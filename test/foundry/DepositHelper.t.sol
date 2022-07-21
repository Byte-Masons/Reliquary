// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "contracts/helpers/DepositHelper.sol";

contract DepositHelperTest is Test {
    DepositHelper helper;
    IReliquary reliquary;
    IERC4626 vault;
    IERC20 weth;
    address constant WETH_WHALE = 0x2400BB4D7221bA530Daee061D5Afe219E9223Eae;

    function setUp() public {
        helper = new DepositHelper(0x90fEC9587624dC4437833Ef3C34C218996B8AB98);
        reliquary = helper.reliquary();
        vault = IERC4626(address(reliquary.poolToken(0)));
        weth = IERC20(vault.asset());

        vm.startPrank(WETH_WHALE, WETH_WHALE);
        weth.approve(address(helper), type(uint).max);
        helper.reliquary().setApprovalForAll(address(helper), true);
    }

    function testCreateNew(uint amount) public {
        amount = bound(amount, 10, weth.balanceOf(WETH_WHALE));
        helper.deposit(0, amount, 0);

        assertEq(reliquary.balanceOf(WETH_WHALE), 1, "no Relic given");
        assertEq(
            reliquary.getPositionForId(_getRelicId()).amount, vault.convertToShares(amount),
            "deposited amount not expected amount"
        );
    }

    function testDepositExisting(uint amountA, uint amountB) public {
        amountA = bound(amountA, 10, type(uint).max / 2);
        amountB = bound(amountB, 10, type(uint).max / 2);
        vm.assume(amountA + amountB <= weth.balanceOf(WETH_WHALE));
        helper.deposit(0, amountA, 0);

        helper.deposit(0, amountB, _getRelicId());
        uint relicAmount = reliquary.getPositionForId(_getRelicId()).amount;
        uint expectedAmount = vault.convertToShares(amountA + amountB);
        assertApproxEqAbs(expectedAmount, relicAmount, 1);
    }

    function testWithdraw(uint amount) public {
        amount = bound(amount, 10, weth.balanceOf(WETH_WHALE));
        helper.deposit(0, amount, 0);

        uint initialBalance = weth.balanceOf(WETH_WHALE);
        helper.withdraw(0, amount, _getRelicId());
        assertEq(weth.balanceOf(WETH_WHALE), initialBalance);
    }

    function _getRelicId() private view returns (uint relicId) {
        relicId = reliquary.tokenOfOwnerByIndex(WETH_WHALE, 0);
    }
}
