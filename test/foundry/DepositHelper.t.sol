// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "contracts/helpers/DepositHelper.sol";
import "contracts/Reliquary.sol";
import "contracts/nft_descriptors/NFTDescriptorSingle4626.sol";
import "contracts/emission_curves/Constant.sol";
import "openzeppelin-contracts/contracts/mocks/ERC20DecimalsMock.sol";
import "openzeppelin-contracts/contracts/mocks/ERC4626Mock.sol";
import "openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";

contract DepositHelperTest is ERC721Holder, Test {
    DepositHelper helper;
    Reliquary reliquary;
    IERC4626 vault;
    ERC20DecimalsMock oath;
    ERC20DecimalsMock weth;

    uint[] wethCurve = [0, 1 days, 7 days, 14 days, 30 days, 90 days, 180 days, 365 days];
    uint[] wethLevels = [100, 120, 150, 200, 300, 400, 500, 750];

    function setUp() public {
        oath = new ERC20DecimalsMock("Oath Token", "OATH", 18);
        reliquary = new Reliquary(
            address(oath),
            address(new Constant())
        );

        weth = new ERC20DecimalsMock("Wrapped Ether", "wETH", 18);
        vault = new ERC4626Mock(weth, "ETH Optimizer", "relETH");

        address nftDescriptor = address(new NFTDescriptorSingle4626(address(reliquary)));
        reliquary.grantRole(keccak256(bytes("OPERATOR")), address(this));
        reliquary.addPool(1000, address(vault), address(0), wethCurve, wethLevels, "ETH Crypt", address(nftDescriptor));

        helper = new DepositHelper(address(reliquary));

        weth.mint(address(this), 1_000_000 ether);
        weth.approve(address(helper), type(uint).max);
        Reliquary(helper.reliquary()).setApprovalForAll(address(helper), true);
    }

    function testCreateNew(uint amount) public {
        amount = bound(amount, 10, weth.balanceOf(address(this)));
        uint relicId = helper.createRelicAndDeposit(0, amount);

        assertEq(reliquary.balanceOf(address(this)), 1, "no Relic given");
        assertEq(
            reliquary.getPositionForId(relicId).amount,
            vault.convertToShares(amount),
            "deposited amount not expected amount"
        );
    }

    function testDepositExisting(uint amountA, uint amountB) public {
        amountA = bound(amountA, 10, type(uint).max / 2);
        amountB = bound(amountB, 10, type(uint).max / 2);
        vm.assume(amountA + amountB <= weth.balanceOf(address(this)));

        uint relicId = helper.createRelicAndDeposit(0, amountA);
        helper.deposit(amountB, relicId);

        uint relicAmount = reliquary.getPositionForId(relicId).amount;
        uint expectedAmount = vault.convertToShares(amountA + amountB);
        assertApproxEqAbs(expectedAmount, relicAmount, 1);
    }

    function testWithdraw(uint amount, bool harvest) public {
        uint initialBalance = weth.balanceOf(address(this));
        amount = bound(amount, 10, initialBalance);

        uint relicId = helper.createRelicAndDeposit(0, amount);
        helper.withdraw(amount, relicId, harvest);

        assertApproxEqAbs(weth.balanceOf(address(this)), initialBalance, 10);
    }
}
