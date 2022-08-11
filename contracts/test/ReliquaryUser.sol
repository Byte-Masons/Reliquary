// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "contracts/interfaces/IReliquary.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

interface Weth is IERC20{
    function deposit() external payable;
}

contract ReliquaryUser is Test {
    IReliquary reliquary;
    IERC4626 wethVault;

    constructor(address _reliquary, address _wethVault) {
        reliquary = IReliquary(_reliquary);
        wethVault = IERC4626(_wethVault);
    }

    function createRelicAndDeposit(uint128 amount) external {
        uint shares = _getTokens(amount);
        reliquary.createRelicAndDeposit(address(this), 0, shares);
    }

    function depositExisting(uint128 amount, uint index) external {
        uint relicId = _getOwnedRelicId(index);
        uint shares = _getTokens(amount);
        reliquary.deposit(shares, relicId);
    }

    function withdraw(uint amount, uint index, bool harvest) external {
        uint relicId = _getOwnedRelicId(index);
        amount = bound(amount, 1, reliquary.getPositionForId(relicId).amount);
        if (harvest) {
            reliquary.withdrawAndHarvest(amount, relicId);
        } else {
            reliquary.withdraw(amount, relicId);
        }
    }

    function harvest(uint index) external {
        uint relicId = _getOwnedRelicId(index);
        reliquary.harvest(relicId);
    }

    function _getOwnedRelicId(uint index) internal returns(uint relicId) {
        uint balance = reliquary.balanceOf(address(this));
        require(balance != 0, "no existing Relics");
        index = bound(index, 0, balance - 1);
        relicId = reliquary.tokenOfOwnerByIndex(address(this), index);
    }

    function _getTokens(uint128 amount) internal returns (uint shares) {
        deal(address(this), amount);
        Weth weth = Weth(wethVault.asset());
        weth.deposit{value: amount}();
        weth.approve(address(wethVault), amount);
        wethVault.deposit(amount, address(reliquary));
        shares = wethVault.balanceOf(address(this));
    }
}
