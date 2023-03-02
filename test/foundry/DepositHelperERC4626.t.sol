// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/mocks/ERC20DecimalsMock.sol";
import "openzeppelin-contracts/contracts/mocks/ERC4626Mock.sol";
import "openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import "contracts/emission_curves/Constant.sol";
import "contracts/helpers/DepositHelperERC4626.sol";
import "contracts/nft_descriptors/NFTDescriptorSingle4626.sol";
import "contracts/Reliquary.sol";

contract DepositHelperERC4626Test is ERC721Holder, Test {
    DepositHelperERC4626 helper;
    Reliquary reliquary;
    IERC4626 vault;
    ERC20DecimalsMock oath;
    WETH weth;

    uint[] wethCurve = [0, 1 days, 7 days, 14 days, 30 days, 90 days, 180 days, 365 days];
    uint[] wethLevels = [100, 120, 150, 200, 300, 400, 500, 750];

    receive() external payable {}

    function setUp() public {
        oath = new ERC20DecimalsMock("Oath Token", "OATH", 18);
        reliquary = new Reliquary(
            address(oath),
            address(new Constant()),
            "Reliquary Deposit",
            "RELIC"
        );

        weth = new WETH();
        vault = new ERC4626Mock(IERC20Metadata(address(weth)), "ETH Optimizer", "relETH");

        address nftDescriptor = address(new NFTDescriptorSingle4626(address(reliquary)));
        reliquary.grantRole(keccak256("OPERATOR"), address(this));
        reliquary.addPool(1000, address(vault), address(0), wethCurve, wethLevels, "ETH Crypt", nftDescriptor, true);

        helper = new DepositHelperERC4626(address(reliquary), address(weth));

        weth.deposit{value: 1_000_000 ether}();
        weth.approve(address(helper), type(uint).max);
        Reliquary(helper.reliquary()).setApprovalForAll(address(helper), true);
    }

    function testCreateNew(uint amount, bool depositETH) public {
        amount = bound(amount, 10, weth.balanceOf(address(this)));
        uint relicId = helper.createRelicAndDeposit{value: depositETH ? amount : 0}(0, amount);

        assertEq(reliquary.balanceOf(address(this)), 1, "no Relic given");
        assertEq(
            reliquary.getPositionForId(relicId).amount,
            vault.convertToShares(amount),
            "deposited amount not expected amount"
        );
    }

    function testDepositExisting(uint amountA, uint amountB, bool aIsETH, bool bIsETH) public {
        amountA = bound(amountA, 10, 500_000 ether);
        amountB = bound(amountB, 10, 1_000_000 ether - amountA);

        uint relicId = helper.createRelicAndDeposit{value: aIsETH ? amountA : 0}(0, amountA);
        helper.deposit{value: bIsETH ? amountB : 0}(amountB, relicId);

        uint relicAmount = reliquary.getPositionForId(relicId).amount;
        uint expectedAmount = vault.convertToShares(amountA + amountB);
        assertApproxEqAbs(expectedAmount, relicAmount, 1);
    }

    function testRevertOnDepositUnauthorized() public {
        uint relicId = helper.createRelicAndDeposit(0, 1);
        vm.expectRevert(bytes("not owner or approved"));
        vm.prank(address(1));
        helper.deposit(1, relicId);
    }

    function testWithdraw(uint amount, bool harvest, bool depositETH, bool withdrawETH) public {
        uint ethInitialBalance = address(this).balance;
        uint wethInitialBalance = weth.balanceOf(address(this));
        amount = bound(amount, 10, wethInitialBalance);

        uint relicId = helper.createRelicAndDeposit{value: depositETH ? amount : 0}(0, amount);
        helper.withdraw(amount, relicId, harvest, withdrawETH);

        uint difference;
        if (depositETH && withdrawETH) {
            difference = ethInitialBalance - address(this).balance;
        } else if (depositETH && !withdrawETH) {
            difference = weth.balanceOf(address(this)) - wethInitialBalance;
        } else if (!depositETH && withdrawETH) {
            difference = address(this).balance - ethInitialBalance;
        } else {
            difference = wethInitialBalance - weth.balanceOf(address(this));
        }

        uint expectedDifference = (depositETH == withdrawETH) ? 0 : amount;
        assertApproxEqAbs(difference, expectedDifference, 10);
    }

    function testRevertOnWithdrawUnauthorized(bool harvest) public {
        uint relicId = helper.createRelicAndDeposit(0, 1);
        vm.expectRevert(bytes("not owner or approved"));
        vm.prank(address(1));
        helper.withdraw(1, relicId, harvest, false);
    }
}
