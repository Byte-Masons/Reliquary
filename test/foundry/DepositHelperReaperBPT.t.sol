// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";
import "contracts/emission_curves/Constant.sol";
import "contracts/helpers/DepositHelperReaperBPT.sol";
import "contracts/nft_descriptors/NFTDescriptor.sol";
import "contracts/Reliquary.sol";

interface IReaperVaultTest is IReaperVault {
    function balance() external view returns (uint);
}

interface IReZapTest is IReZap {
    function findStepsIn(address zapInToken, address BPT, uint tokenInAmount) external returns (Step[] memory);
    function findStepsOut(address zapOutToken, address BPT, uint bptAmount) external returns (Step[] memory);
}

interface IWftm is IERC20 {
    function deposit() external payable returns (uint);
}

contract DepositHelperReaperBPTTest is ERC721Holder, Test {
    DepositHelperReaperBPT helper;
    IReZapTest reZap;
    Reliquary reliquary;
    IReaperVaultTest vault;
    address bpt;
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
            address(new Constant()),
            "Reliquary Deposit",
            "RELIC"
        );

        vault = IReaperVaultTest(0xA817164Cb1BF8bdbd96C502Bbea93A4d2300CBe1);
        bpt = address(vault.token());

        address nftDescriptor = address(new NFTDescriptor(address(reliquary)));
        reliquary.grantRole(keccak256("OPERATOR"), address(this));
        reliquary.addPool(
            1000, address(vault), address(0), quartetCurve, quartetLevels, "A Late Quartet", nftDescriptor, true
        );

        reZap = IReZapTest(0x6E87672e547D40285C8FdCE1139DE4bc7CBF2127);
        helper = new DepositHelperReaperBPT(address(reliquary), address(reZap));

        wftm = IWftm(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
        wftm.deposit{value: 1_000_000 ether}();
        wftm.approve(address(helper), type(uint).max);
        Reliquary(helper.reliquary()).setApprovalForAll(address(helper), true);
    }

    function testCreateNew(uint amount, bool depositFTM) public {
        amount = bound(amount, 1 ether, wftm.balanceOf(address(this)));
        IReZap.Step[] memory steps = reZap.findStepsIn(address(wftm), bpt, amount);
        (uint relicId, uint shares) = helper.createRelicAndDeposit{value: depositFTM ? amount : 0}(steps, 0, amount);

        assertEq(wftm.balanceOf(address(helper)), 0);
        assertEq(reliquary.balanceOf(address(this)), 1, "no Relic given");
        assertEq(reliquary.getPositionForId(relicId).amount, shares, "deposited amount not expected amount");
    }

    function testDepositExisting(uint amountA, uint amountB, bool aIsFTM, bool bIsFTM) public {
        amountA = bound(amountA, 1 ether, 500_000 ether);
        amountB = bound(amountB, 1 ether, 1_000_000 ether - amountA);

        IReZap.Step[] memory stepsA = reZap.findStepsIn(address(wftm), bpt, amountA);
        (uint relicId, uint sharesA) = helper.createRelicAndDeposit{value: aIsFTM ? amountA : 0}(stepsA, 0, amountA);
        IReZap.Step[] memory stepsB = reZap.findStepsIn(address(wftm), bpt, amountB);
        uint sharesB = helper.deposit{value: bIsFTM ? amountB : 0}(stepsB, amountB, relicId);

        assertEq(wftm.balanceOf(address(helper)), 0);
        uint relicAmount = reliquary.getPositionForId(relicId).amount;
        assertEq(relicAmount, sharesA + sharesB);
    }

    function testRevertOnDepositUnauthorized() public {
        IReZap.Step[] memory stepsA = reZap.findStepsIn(address(wftm), bpt, 1 ether);
        (uint relicId,) = helper.createRelicAndDeposit(stepsA, 0, 1 ether);
        IReZap.Step[] memory stepsB = reZap.findStepsIn(address(wftm), bpt, 1 ether);
        vm.expectRevert(bytes("not owner or approved"));
        vm.prank(address(1));
        helper.deposit(stepsB, 1 ether, relicId);
    }

    function testWithdraw(uint amount, bool harvest, bool depositFTM, bool withdrawFTM) public {
        uint ftmInitialBalance = address(this).balance;
        uint wftmInitialBalance = wftm.balanceOf(address(this));
        amount = bound(amount, 1 ether, 1_000_000 ether);

        IReZap.Step[] memory stepsIn = reZap.findStepsIn(address(wftm), bpt, amount);
        (uint relicId, uint shares) = helper.createRelicAndDeposit{value: depositFTM ? amount : 0}(stepsIn, 0, amount);
        IReZap.Step[] memory stepsOut =
            reZap.findStepsOut(address(wftm), bpt, shares * vault.balance() / vault.totalSupply());
        helper.withdraw(stepsOut, shares, relicId, harvest, withdrawFTM);

        uint difference;
        if (depositFTM && withdrawFTM) {
            difference = ftmInitialBalance - address(this).balance;
        } else if (depositFTM && !withdrawFTM) {
            difference = wftm.balanceOf(address(this)) - wftmInitialBalance;
        } else if (!depositFTM && withdrawFTM) {
            difference = address(this).balance - ftmInitialBalance;
        } else {
            difference = wftmInitialBalance - wftm.balanceOf(address(this));
        }

        // allow for 0.5% slippage after 0.1% security fee
        uint afterFee = amount - amount * 10 / 10_000;
        if (depositFTM == withdrawFTM) {
            assertTrue(difference <= afterFee * 5 / 1000);
        } else {
            assertApproxEqRel(difference, afterFee, 5e15);
        }
    }

    function testRevertOnWithdrawUnauthorized(bool harvest, bool isETH) public {
        IReZap.Step[] memory stepsIn = reZap.findStepsIn(address(wftm), bpt, 1 ether);
        (uint relicId, uint shares) = helper.createRelicAndDeposit(stepsIn, 0, 1 ether);
        IReZap.Step[] memory stepsOut =
            reZap.findStepsOut(address(wftm), bpt, shares * vault.balance() / vault.totalSupply());
        vm.expectRevert(bytes("not owner or approved"));
        vm.prank(address(1));
        helper.withdraw(stepsOut, shares, relicId, harvest, isETH);
    }
}
