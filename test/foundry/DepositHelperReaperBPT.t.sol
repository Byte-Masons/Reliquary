// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";
import "contracts/helpers/DepositHelperReaperBPT.sol";
import "contracts/nft_descriptors/NFTDescriptor.sol";
import "contracts/Reliquary.sol";
import "contracts/curves/LinearCurve.sol";

interface IReaperVaultTest is IReaperVault {
    function balance() external view returns (uint256);
}

interface IReZapTest is IReZap {
    function findStepsIn(address zapInToken, address BPT, uint256 tokenInAmount)
        external
        returns (Step[] memory);

    function findStepsOut(address zapOutToken, address BPT, uint256 bptAmount)
        external
        returns (Step[] memory);
}

interface IWftm is IERC20 {
    function deposit() external payable returns (uint256);
}

contract DepositHelperReaperBPTTest is ERC721Holder, Test {
    DepositHelperReaperBPT helper;
    IReZapTest reZap;
    Reliquary reliquary;
    IReaperVaultTest vault;
    LinearCurve linearCurve;
    address bpt;
    IERC20 oath;
    IWftm wftm;
    uint256 emissionRate = 1e17;

    // Linear function config (to config)
    uint256 slope = 100; // Increase of multiplier every second
    uint256 minMultiplier = 365 days * 100; // Arbitrary (but should be coherent with slope)

    receive() external payable {}

    function setUp() public {
        vm.createSelectFork("fantom", 53341452);

        oath = IERC20(0x21Ada0D2aC28C3A5Fa3cD2eE30882dA8812279B6);
        reliquary = new Reliquary(address(oath), emissionRate, "Reliquary Deposit", "RELIC");
        linearCurve = new LinearCurve(slope, minMultiplier);

        vault = IReaperVaultTest(0xA817164Cb1BF8bdbd96C502Bbea93A4d2300CBe1);
        bpt = address(vault.token());

        address nftDescriptor = address(new NFTDescriptor(address(reliquary)));
        reliquary.grantRole(keccak256("OPERATOR"), address(this));
        deal(address(vault), address(this), 1);
        vault.approve(address(reliquary), 1); // approve 1 wei to bootstrap the pool
        reliquary.addPool(
            1000,
            address(vault),
            address(0),
            linearCurve,
            "A Late Quartet",
            nftDescriptor,
            true,
            address(this)
        );

        reZap = IReZapTest(0x6E87672e547D40285C8FdCE1139DE4bc7CBF2127);
        helper = new DepositHelperReaperBPT(reliquary, reZap);

        wftm = IWftm(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
        wftm.deposit{value: 1_000_000 ether}();
        wftm.approve(address(helper), type(uint256).max);
        helper.reliquary().setApprovalForAll(address(helper), true);
    }

    function testCreateNew(uint256 amount, bool depositFTM) public {
        amount = bound(amount, 1 ether, wftm.balanceOf(address(this)));
        IReZap.Step[] memory steps = reZap.findStepsIn(address(wftm), bpt, amount);
        (uint256 relicId, uint256 shares) =
            helper.createRelicAndDeposit{value: depositFTM ? amount : 0}(steps, 0, amount);

        assertEq(wftm.balanceOf(address(helper)), 0);
        assertEq(reliquary.balanceOf(address(this)), 2, "no Relic given");
        assertEq(
            reliquary.getPositionForId(relicId).amount,
            shares,
            "deposited amount not expected amount"
        );
    }

    function testDepositExisting(uint256 amountA, uint256 amountB, bool aIsFTM, bool bIsFTM)
        public
    {
        amountA = bound(amountA, 1 ether, 500_000 ether);
        amountB = bound(amountB, 1 ether, 1_000_000 ether - amountA);

        IReZap.Step[] memory stepsA = reZap.findStepsIn(address(wftm), bpt, amountA);
        (uint256 relicId, uint256 sharesA) =
            helper.createRelicAndDeposit{value: aIsFTM ? amountA : 0}(stepsA, 0, amountA);
        IReZap.Step[] memory stepsB = reZap.findStepsIn(address(wftm), bpt, amountB);
        uint256 sharesB =
            helper.deposit{value: bIsFTM ? amountB : 0}(stepsB, amountB, relicId, true);

        assertEq(wftm.balanceOf(address(helper)), 0);
        uint256 relicAmount = reliquary.getPositionForId(relicId).amount;
        assertEq(relicAmount, sharesA + sharesB);
    }

    function testRevertOnDepositUnauthorized() public {
        IReZap.Step[] memory stepsA = reZap.findStepsIn(address(wftm), bpt, 1 ether);
        (uint256 relicId,) = helper.createRelicAndDeposit(stepsA, 0, 1 ether);
        IReZap.Step[] memory stepsB = reZap.findStepsIn(address(wftm), bpt, 1 ether);
        vm.expectRevert(bytes("not approved or owner"));
        vm.prank(address(1));
        helper.deposit(stepsB, 1 ether, relicId, false);
    }

    function testWithdraw(uint256 amount, bool harvest, bool depositFTM, bool withdrawFTM) public {
        uint256 ftmInitialBalance = address(this).balance;
        uint256 wftmInitialBalance = wftm.balanceOf(address(this));
        amount = bound(amount, 1 ether, 1_000_000 ether);

        IReZap.Step[] memory stepsIn = reZap.findStepsIn(address(wftm), bpt, amount);
        (uint256 relicId, uint256 shares) =
            helper.createRelicAndDeposit{value: depositFTM ? amount : 0}(stepsIn, 0, amount);
        IReZap.Step[] memory stepsOut =
            reZap.findStepsOut(address(wftm), bpt, (shares * vault.balance()) / vault.totalSupply());
        helper.withdraw(stepsOut, shares, relicId, harvest, withdrawFTM);

        uint256 difference;
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
        uint256 afterFee = amount - (amount * 10) / 10_000;
        if (depositFTM == withdrawFTM) {
            assertTrue(difference <= (afterFee * 5) / 1000);
        } else {
            assertApproxEqRel(difference, afterFee, 5e15);
        }
    }

    function testRevertOnWithdrawUnauthorized(bool harvest, bool isETH) public {
        IReZap.Step[] memory stepsIn = reZap.findStepsIn(address(wftm), bpt, 1 ether);
        (uint256 relicId, uint256 shares) = helper.createRelicAndDeposit(stepsIn, 0, 1 ether);
        IReZap.Step[] memory stepsOut =
            reZap.findStepsOut(address(wftm), bpt, (shares * vault.balance()) / vault.totalSupply());
        vm.expectRevert(bytes("not approved or owner"));
        vm.prank(address(1));
        helper.withdraw(stepsOut, shares, relicId, harvest, isETH);
    }
}
