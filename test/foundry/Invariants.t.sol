// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "scripts/Deploy.s.sol";
import "contracts/test/ReliquaryUser.sol";
import "contracts/test/Skipper.sol";

interface IERC20Mint {
    function mint(address to, uint amount) external;
}

contract Invariants is Test {
    Deploy deployer;
    Reliquary reliquary;
    DepositHelper helper;
    IERC4626 wethCrypt;

    address[] private _targetContracts;

    function setUp() public {
        deployer = new Deploy();
        deployer.run();
        reliquary = Reliquary(deployer.reliquary());
        helper = deployer.helper();

        IERC20Mint oath = IERC20Mint(address(reliquary.oath()));
        vm.prank(deployer.MULTISIG());
        oath.mint(address(reliquary), 100_000_000 ether);

        wethCrypt = IERC4626(address(reliquary.poolToken(0)));

        ReliquaryUser user = new ReliquaryUser(address(reliquary), address(wethCrypt));
        Skipper skipper = new Skipper();

        _targetContracts.push(address(user));
        _targetContracts.push(address(skipper));
    }

    // would not hold if poolToken were transferred to reliquary outside deposit functions
    function invariantLevelBalancesEqBalanceOf() public {
        uint[] memory totals = new uint[](reliquary.poolLength());
        for (uint i; i < totals.length; ++i) {
            LevelInfo memory level = reliquary.getLevelInfo(i);
            for (uint j; j < level.balance.length; ++j) {
                totals[i] += level.balance[j];
            }
            uint balance = reliquary.poolToken(i).balanceOf(address(reliquary));
            assertEq(totals[i], balance);
        }
    }

    function targetContracts() public view returns (address[] memory targetContracts_) {
        require(_targetContracts.length != uint256(0), "NO_TARGET_CONTRACTS");
        return _targetContracts;
    }
}
