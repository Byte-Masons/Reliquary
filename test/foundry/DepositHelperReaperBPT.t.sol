// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";
import "contracts/emission_curves/Constant.sol";
import "contracts/helpers/DepositHelperReaperBPT.sol";
import "contracts/nft_descriptors/NFTDescriptor.sol";
import "contracts/Reliquary.sol";

interface IWftm is IERC20 {
    function deposit() external payable returns (uint);
}

contract DepositHelperReaperBPTTest is ERC721Holder, Test {
    DepositHelperReaperBPT helper;
    Reliquary reliquary;
    IReaperVault vault;
    IERC20 oath;
    IWftm wftm;

    uint[] quartetCurve = [0, 1 days, 7 days, 14 days, 30 days, 90 days, 180 days, 365 days];
    uint[] quartetLevels = [100, 120, 150, 200, 300, 400, 500, 750];

    receive() external payable {}

    function setUp() public {
        vm.createSelectFork("fantom", 53341452);

        oath = IERC20(0x21Ada0D2aC28C3A5Fa3cD2eE30882dA8812279B6);
        reliquary = new Reliquary(
            address(oath),
            address(new Constant())
        );

        vault = IReaperVault(0xA817164Cb1BF8bdbd96C502Bbea93A4d2300CBe1);

        address nftDescriptor = address(new NFTDescriptor(address(reliquary)));
        reliquary.grantRole(keccak256("OPERATOR"), address(this));
        reliquary.addPool(
            1000, address(vault), address(0), quartetCurve, quartetLevels, "A Late Quartet", nftDescriptor
        );

        helper = new DepositHelperReaperBPT(address(reliquary), 0x6E87672e547D40285C8FdCE1139DE4bc7CBF2127);

        wftm = IWftm(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
        wftm.deposit{value: 1_000_000 ether}();
        wftm.approve(address(helper), type(uint).max);
        Reliquary(helper.reliquary()).setApprovalForAll(address(helper), true);
    }

    function testCreateNew(uint amount) public {
        amount = bound(amount, 10 ether, wftm.balanceOf(address(this)));
        (uint relicId, uint shares) = helper.createRelicAndDeposit(address(wftm), 0, amount);

        assertEq(wftm.balanceOf(address(helper)), 0);
        assertEq(reliquary.balanceOf(address(this)), 1, "no Relic given");
        assertEq(reliquary.getPositionForId(relicId).amount, shares, "deposited amount not expected amount");
    }

    function testDepositExisting(uint amountA, uint amountB) public {
        amountA = bound(amountA, 10 ether, 500_000 ether);
        amountB = bound(amountB, 10 ether, 1_000_000 ether - amountA);

        (uint relicId, uint sharesA) = helper.createRelicAndDeposit(address(wftm), 0, amountA);
        uint sharesB = helper.deposit(address(wftm), amountB, relicId);

        assertEq(wftm.balanceOf(address(helper)), 0);
        uint relicAmount = reliquary.getPositionForId(relicId).amount;
        assertEq(relicAmount, sharesA + sharesB);
    }

    function testRevertOnDepositUnauthorized() public {
        (uint relicId,) = helper.createRelicAndDeposit(address(wftm), 0, 1 ether);
        vm.expectRevert(bytes("not owner or approved"));
        vm.prank(address(1));
        helper.deposit(address(wftm), 1, relicId);
    }

    function testWithdraw(uint amount, bool harvest) public {
        uint initialBalance = address(this).balance;
        amount = bound(amount, 1 ether, 1_000_000 ether);

        (uint relicId, uint shares) = helper.createRelicAndDeposit(address(wftm), 0, amount);
        helper.withdraw(address(wftm), shares, relicId, harvest);

        assertApproxEqRel(address(this).balance, initialBalance - amount * 10 / 10_000, 1e16);
    }

    function testRevertOnWithdrawUnauthorized(bool harvest) public {
        (uint relicId,) = helper.createRelicAndDeposit(address(wftm), 0, 1 ether);
        vm.expectRevert(bytes("not owner or approved"));
        vm.prank(address(1));
        helper.withdraw(address(wftm), 1 ether, relicId, harvest);
    }
}
