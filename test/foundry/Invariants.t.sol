// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "contracts/Reliquary.sol";
import "contracts/emission_curves/Constant.sol";
import "contracts/nft_descriptors/NFTDescriptor.sol";
import "contracts/test/ReliquaryUser.sol";
import "contracts/test/Skipper.sol";
import "contracts/test/TestToken.sol";

contract Invariants is Test {
    Reliquary reliquary;

    address[] private _targetContracts;

    uint[] curve = [0, 1 days, 7 days, 14 days, 30 days, 90 days, 180 days, 365 days];
    uint[] levels = [100, 120, 150, 200, 300, 400, 500, 750];

    function setUp() public {
        TestToken oath = new TestToken("Oath Token", "OATH", 18);
        reliquary = new Reliquary(oath, IEmissionCurve(address(new Constant())));
        oath.mint(address(reliquary), 100_000_000 ether);
        TestToken testToken = new TestToken("Test Token", "TT", 6);
        INFTDescriptor nftDescriptor = INFTDescriptor(new NFTDescriptor(IReliquary(reliquary)));
        reliquary.grantRole(keccak256(bytes("OPERATOR")), address(this));
        reliquary.addPool(1000, testToken, IRewarder(address(0)), curve, levels, block.timestamp, "Test Token", nftDescriptor);

        ReliquaryUser user = new ReliquaryUser(address(reliquary), address(testToken));
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
