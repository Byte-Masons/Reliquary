// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "contracts/interfaces/IReliquary.sol";
import "./TestToken.sol";
import "openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

interface Weth is IERC20 {
    function deposit() external payable;
}

contract ReliquaryUser is ERC721Holder, Test {
    IReliquary reliquary;
    TestToken testToken;

    constructor(address _reliquary, address _testToken) {
        reliquary = IReliquary(_reliquary);
        testToken = TestToken(_testToken);
    }

    function createRelicAndDeposit(uint128 amount) external {
        _getTokens(amount);
        reliquary.createRelicAndDeposit(address(this), 0, amount);
    }

    function depositExisting(uint128 amount, uint index) external {
        uint relicId = _getOwnedRelicId(index);
        _getTokens(amount);
        reliquary.deposit(amount, relicId);
    }

    function withdraw(uint amount, uint index, bool _harvest) external {
        uint relicId = _getOwnedRelicId(index);
        amount = bound(amount, 1, reliquary.getPositionForId(relicId).amount);
        if (_harvest) {
            reliquary.withdrawAndHarvest(amount, relicId, address(this));
        } else {
            reliquary.withdraw(amount, relicId);
        }
    }

    function harvest(uint index) external {
        uint relicId = _getOwnedRelicId(index);
        reliquary.harvest(relicId, address(this));
    }

    function split(uint amount, uint index) external {
        uint relicId = _getOwnedRelicId(index);
        amount = bound(amount, 1, reliquary.getPositionForId(relicId).amount);
        reliquary.split(relicId, amount, address(this));
    }

    function shift(uint amount, uint fromIndex, uint toIndex) external {
        vm.assume(fromIndex != toIndex);
        uint fromId = _getOwnedRelicId(fromIndex);
        uint toId = _getOwnedRelicId(toIndex);
        amount = bound(amount, 1, reliquary.getPositionForId(fromId).amount);
        reliquary.shift(fromId, toId, amount);
    }

    function merge(uint fromIndex, uint toIndex) external {
        vm.assume(fromIndex != toIndex);
        uint fromId = _getOwnedRelicId(fromIndex);
        uint toId = _getOwnedRelicId(toIndex);
        reliquary.merge(fromId, toId);
    }

    function emergencyWithdraw(uint index) external {
        uint relicId = _getOwnedRelicId(index);
        reliquary.emergencyWithdraw(relicId);
    }

    function _getOwnedRelicId(uint index) internal view returns (uint relicId) {
        uint balance = reliquary.balanceOf(address(this));
        require(balance != 0, "no existing Relics");
        index = bound(index, 0, balance - 1);
        relicId = reliquary.tokenOfOwnerByIndex(address(this), index);
    }

    function _getTokens(uint128 amount) internal {
        vm.assume(amount != 0);
        testToken.mint(address(this), amount);
        testToken.approve(address(reliquary), amount);
    }
}
