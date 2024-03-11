// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/mocks/ERC20DecimalsMock.sol";
import "openzeppelin-contracts/contracts/mocks/ERC4626Mock.sol";
import "openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import "contracts/helpers/DepositHelperERC4626.sol";
import "contracts/nft_descriptors/NFTDescriptorSingle4626.sol";
import "contracts/Reliquary.sol";
import "contracts/curves/LinearCurve.sol";

contract DepositHelperERC4626Test is ERC721Holder, Test {
    DepositHelperERC4626 helper;
    Reliquary reliquary;
    IERC4626 vault;
    ERC20DecimalsMock oath;
    WETH weth;
    LinearCurve linearCurve;
    uint256 emissionRate = 1e17;

    // Linear function config (to config)
    uint256 slope = 100; // Increase of multiplier every second
    uint256 minMultiplier = 365 days * 100; // Arbitrary (but should be coherent with slope)

    receive() external payable {}

    function setUp() public {
        oath = new ERC20DecimalsMock("Oath Token", "OATH", 18);
        reliquary = new Reliquary(address(oath), 1e17, "Reliquary Deposit", "RELIC");

        weth = new WETH();
        vault = new ERC4626Mock(IERC20Metadata(address(weth)), "ETH Optimizer", "relETH");
        linearCurve = new LinearCurve(slope, minMultiplier);

        address nftDescriptor = address(new NFTDescriptorSingle4626(address(reliquary)));
        reliquary.grantRole(keccak256("OPERATOR"), address(this));
        reliquary.addPool(
            1000, address(vault), address(0), linearCurve, "ETH Crypt", nftDescriptor, true
        );

        helper = new DepositHelperERC4626(reliquary, address(weth));

        weth.deposit{value: 1_000_000 ether}();
        weth.approve(address(helper), type(uint256).max);
        helper.reliquary().setApprovalForAll(address(helper), true);
    }

    function testCreateNew(uint256 amount, bool depositETH) public {
        amount = bound(amount, 10, weth.balanceOf(address(this)));
        uint256 relicId = helper.createRelicAndDeposit{value: depositETH ? amount : 0}(0, amount);

        assertEq(reliquary.balanceOf(address(this)), 1, "no Relic given");
        assertEq(
            reliquary.getPositionForId(relicId).amount,
            vault.convertToShares(amount),
            "deposited amount not expected amount"
        );
    }

    function testDepositExisting(uint256 amountA, uint256 amountB, bool aIsETH, bool bIsETH)
        public
    {
        amountA = bound(amountA, 10, 500_000 ether);
        amountB = bound(amountB, 10, 1_000_000 ether - amountA);

        uint256 relicId = helper.createRelicAndDeposit{value: aIsETH ? amountA : 0}(0, amountA);
        helper.deposit{value: bIsETH ? amountB : 0}(amountB, relicId);

        uint256 relicAmount = reliquary.getPositionForId(relicId).amount;
        uint256 expectedAmount = vault.convertToShares(amountA + amountB);
        assertApproxEqAbs(expectedAmount, relicAmount, 1);
    }

    function testRevertOnDepositUnauthorized() public {
        uint256 relicId = helper.createRelicAndDeposit(0, 1);
        vm.expectRevert(bytes("not approved or owner"));
        vm.prank(address(1));
        helper.deposit(1, relicId);
    }

    function testWithdraw(uint256 amount, bool harvest, bool depositETH, bool withdrawETH) public {
        uint256 ethInitialBalance = address(this).balance;
        uint256 wethInitialBalance = weth.balanceOf(address(this));
        amount = bound(amount, 10, wethInitialBalance);

        uint256 relicId = helper.createRelicAndDeposit{value: depositETH ? amount : 0}(0, amount);
        helper.withdraw(amount, relicId, harvest, withdrawETH);

        uint256 difference;
        if (depositETH && withdrawETH) {
            difference = ethInitialBalance - address(this).balance;
        } else if (depositETH && !withdrawETH) {
            difference = weth.balanceOf(address(this)) - wethInitialBalance;
        } else if (!depositETH && withdrawETH) {
            difference = address(this).balance - ethInitialBalance;
        } else {
            difference = wethInitialBalance - weth.balanceOf(address(this));
        }

        uint256 expectedDifference = (depositETH == withdrawETH) ? 0 : amount;
        assertApproxEqAbs(difference, expectedDifference, 10);
    }

    function testRevertOnWithdrawUnauthorized(bool harvest) public {
        uint256 relicId = helper.createRelicAndDeposit(0, 1);
        vm.expectRevert(bytes("not approved or owner"));
        vm.prank(address(1));
        helper.withdraw(1, relicId, harvest, false);
    }
}
