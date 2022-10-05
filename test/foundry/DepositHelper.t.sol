// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "contracts/helpers/DepositHelper.sol";
import "contracts/Reliquary.sol";
import "contracts/nft_descriptors/NFTDescriptorSingle4626.sol";
import "contracts/emission_curves/Constant.sol";

contract DepositHelperTest is Test {
    DepositHelper helper;
    Reliquary reliquary;
    IERC4626 vault;
    IERC20 weth;
    address constant WETH_WHALE = 0x2400BB4D7221bA530Daee061D5Afe219E9223Eae;

    uint[] wethCurve = [0, 1 days, 7 days, 14 days, 30 days, 90 days, 180 days, 365 days];
    uint[] wethLevels = [100, 120, 150, 200, 300, 400, 500, 750];

    function setUp() public {
        vm.createSelectFork("fantom", 43052549);

        reliquary = new Reliquary(
            IERC20(0x21Ada0D2aC28C3A5Fa3cD2eE30882dA8812279B6),
            IEmissionCurve(address(new Constant()))
        );
        vault = IERC4626(0x58C60B6dF933Ff5615890dDdDCdD280bad53f1C1);
        INFTDescriptor nftDescriptor = INFTDescriptor(new NFTDescriptorSingle4626(IReliquary(reliquary)));
        reliquary.grantRole(keccak256(bytes("OPERATOR")), address(this));
        reliquary.addPool(1000, vault, IRewarder(address(0)), wethCurve, wethLevels, "ETH Crypt", nftDescriptor);

        helper = new DepositHelper(reliquary);
        weth = IERC20(vault.asset());

        vm.startPrank(WETH_WHALE);
        weth.approve(address(helper), type(uint).max);
        helper.reliquary().setApprovalForAll(address(helper), true);
        vm.stopPrank();
    }

    function testCreateNew(uint amount) public {
        amount = bound(amount, 10, weth.balanceOf(WETH_WHALE));
        vm.prank(WETH_WHALE);
        uint relicId = helper.createRelicAndDeposit(0, amount);

        assertEq(reliquary.balanceOf(WETH_WHALE), 1, "no Relic given");
        assertEq(
            reliquary.getPositionForId(relicId).amount, vault.convertToShares(amount),
            "deposited amount not expected amount"
        );
    }

    function testDepositExisting(uint amountA, uint amountB) public {
        amountA = bound(amountA, 10, type(uint).max / 2);
        amountB = bound(amountB, 10, type(uint).max / 2);
        vm.assume(amountA + amountB <= weth.balanceOf(WETH_WHALE));

        vm.startPrank(WETH_WHALE);
        uint relicId = helper.createRelicAndDeposit(0, amountA);
        helper.deposit(amountB, relicId);
        vm.stopPrank();

        uint relicAmount = reliquary.getPositionForId(relicId).amount;
        uint expectedAmount = vault.convertToShares(amountA + amountB);
        assertApproxEqAbs(expectedAmount, relicAmount, 1);
    }

    function testWithdraw(uint amount, bool harvest) public {
        uint initialBalance = weth.balanceOf(WETH_WHALE);
        amount = bound(amount, 10, initialBalance);

        vm.startPrank(WETH_WHALE);
        uint relicId = helper.createRelicAndDeposit(0, amount);
        helper.withdraw(amount, relicId, harvest);
        vm.stopPrank();

        assertApproxEqAbs(weth.balanceOf(WETH_WHALE), initialBalance, 10);
    }
}
