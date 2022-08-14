// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "scripts/Deploy.s.sol";

interface IERC20Mint {
    function mint(address to, uint amount) external;
}

contract EndToEndTest is Test {
    using stdStorage for StdStorage;

    Deploy deployer;
    Reliquary reliquary;
    DepositHelper helper;
    IERC4626 wethCrypt;

    function setUp() public {
        deployer = new Deploy();
        deployer.run();
        reliquary = Reliquary(deployer.reliquary());
        helper = deployer.helper();

        IERC20Mint oath = IERC20Mint(address(reliquary.oath()));
        vm.prank(deployer.MULTISIG());
        oath.mint(address(reliquary), 100_000_000 ether);

        wethCrypt = IERC4626(address(reliquary.poolToken(0)));
        address weth = wethCrypt.asset();
        stdstore.target(weth).sig("balanceOf(address)").with_key(address(1)).checked_write(100 ether);
    }

    function testPermissions() public {
        assertEq(reliquary.getRoleMemberCount(reliquary.DEFAULT_ADMIN_ROLE()), 1);
        assertEq(reliquary.getRoleMember(reliquary.DEFAULT_ADMIN_ROLE(), 0), deployer.MULTISIG());
        assertEq(reliquary.getRoleMemberCount(deployer.OPERATOR()), 1);
        assertEq(reliquary.getRoleMember(deployer.OPERATOR(), 0), deployer.MULTISIG());
        assertEq(reliquary.getRoleMemberCount(deployer.EMISSION_CURVE()), 1);
        assertEq(reliquary.getRoleMember(deployer.EMISSION_CURVE(), 0), deployer.MULTISIG());
    }

    function testRelicUsageCycle() public {
        vm.startPrank(address(1));

        IERC20 weth = IERC20(wethCrypt.asset());
        weth.approve(address(helper), type(uint).max);
        uint relicId = helper.createRelicAndDeposit(0, 1 ether);

        skip(10 days);
        reliquary.setApprovalForAll(address(helper), true);
        helper.deposit(25 ether, relicId);
        skip(180 days);
        reliquary.updatePosition(relicId);

        console.log(reliquary.tokenURI(relicId));

        uint newId = helper.createRelicAndDeposit(0, 10);
        reliquary.shift(relicId, newId, wethCrypt.convertToShares(15 ether));
        console.log(reliquary.tokenURI(relicId));
        console.log(reliquary.tokenURI(newId));

        helper.withdraw(wethCrypt.convertToAssets(reliquary.getPositionForId(relicId).amount), relicId, false);
        helper.withdraw(wethCrypt.convertToAssets(reliquary.getPositionForId(newId).amount), newId, false);
        assertApproxEqRel(weth.balanceOf(address(1)), 100 ether, 2e14);

        vm.stopPrank();
    }
}
