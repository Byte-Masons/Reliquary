// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IReliquary} from "../interfaces/IReliquary.sol";

interface IWeth is IERC20 {
    function deposit() external payable;
    function withdraw(uint amount) external;
}

contract DepositHelperERC4626 {
    using Address for address payable;
    using SafeERC20 for IERC20;

    address public immutable reliquary;
    address public immutable weth;

    constructor(address _reliquary, address _weth) {
        reliquary = _reliquary;
        weth = _weth;
    }

    receive() external payable {}

    function deposit(uint amount, uint relicId, bool isETH) external payable {
        IReliquary _reliquary = IReliquary(reliquary);
        require(_reliquary.isApprovedOrOwner(msg.sender, relicId), "not owner or approved");

        IERC4626 vault = _prepareDeposit(_reliquary.getPositionForId(relicId).poolId, amount, isETH);
        _reliquary.deposit(vault.balanceOf(address(this)), relicId);
    }

    function createRelicAndDeposit(uint pid, uint amount, bool isETH) external payable returns (uint relicId) {
        IERC4626 vault = _prepareDeposit(pid, amount, isETH);
        relicId = IReliquary(reliquary).createRelicAndDeposit(msg.sender, pid, vault.balanceOf(address(this)));
    }

    function withdraw(uint amount, uint relicId, bool harvest, bool isETH) external {
        IReliquary _reliquary = IReliquary(reliquary);
        require(_reliquary.isApprovedOrOwner(msg.sender, relicId), "not owner or approved");

        uint pid = _reliquary.getPositionForId(relicId).poolId;
        IERC4626 vault = IERC4626(_reliquary.poolToken(pid));

        if (harvest) {
            _reliquary.withdrawAndHarvest(vault.convertToShares(amount), relicId, msg.sender);
        } else {
            _reliquary.withdraw(vault.convertToShares(amount), relicId);
        }

        if (isETH) {
            IWeth _weth = IWeth(weth);
            require(vault.asset() == address(weth), "not an ether vault");
            vault.withdraw(vault.maxWithdraw(address(this)), address(this), address(this));
            _weth.withdraw(amount);
            payable(msg.sender).sendValue(amount);
        } else {
            vault.withdraw(vault.maxWithdraw(address(this)), msg.sender, address(this));
        }
    }

    function _prepareDeposit(uint pid, uint amount, bool isETH) internal returns (IERC4626 vault) {
        vault = IERC4626(IReliquary(reliquary).poolToken(pid));
        IERC20 token = IERC20(vault.asset());
        if (isETH) {
            require(amount == msg.value, "ether amount mismatch");
            IWeth _weth = IWeth(weth);
            require(address(token) == address(_weth), "not an ether vault");
            _weth.deposit{value: msg.value}();
        } else {
            require(msg.value == 0, "sending unused ether");
            token.safeTransferFrom(msg.sender, address(this), amount);
        }

        if (token.allowance(address(this), address(vault)) == 0) {
            token.approve(address(vault), type(uint).max);
        }
        vault.deposit(amount, address(this));

        if (vault.allowance(address(this), address(reliquary)) == 0) {
            vault.approve(reliquary, type(uint).max);
        }
    }
}
