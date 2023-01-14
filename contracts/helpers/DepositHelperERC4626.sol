// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IReliquary} from "../interfaces/IReliquary.sol";

interface IWeth is IERC20 {
    function deposit() external payable;
    function withdraw(uint amount) external;
}

/// @title Helper contract that allows depositing to and withdrawing from Reliquary pools of an ERC4626 vault in a
/// single transaction using the vault's underlying asset.
contract DepositHelperERC4626 is Ownable {
    using Address for address payable;
    using SafeERC20 for IERC20;

    address public immutable reliquary;
    address public immutable weth;

    constructor(address _reliquary, address _weth) {
        reliquary = _reliquary;
        weth = _weth;
    }

    receive() external payable {}

    /// @notice Deposit `amount` of ERC20 tokens (or native ether for a supported pool) into existing Relic `relicId`.
    function deposit(uint amount, uint relicId) external payable {
        IReliquary _reliquary = IReliquary(reliquary);
        require(_reliquary.isApprovedOrOwner(msg.sender, relicId), "not owner or approved");

        IERC4626 vault = _prepareDeposit(_reliquary.getPositionForId(relicId).poolId, amount);
        _reliquary.deposit(vault.balanceOf(address(this)), relicId);
    }

    /// @notice Send `amount` of ERC20 tokens (or native ether for a supported pool) and create a new Relic in pool `pid`.
    function createRelicAndDeposit(uint pid, uint amount) external payable returns (uint relicId) {
        IERC4626 vault = _prepareDeposit(pid, amount);
        relicId = IReliquary(reliquary).createRelicAndDeposit(msg.sender, pid, vault.balanceOf(address(this)));
    }

    /**
     * @notice Withdraw underlying tokens from the Relic.
     * @param amount Amount of underlying token to withdraw.
     * @param relicId The NFT ID of the Relic for the position you are withdrawing from.
     * @param harvest Whether to also harvest pending rewards to `msg.sender`.
     * @param giveEther Whether to withdraw the underlying tokens as native ether instead of wrapped.
     * Only for supported pools.
     */
    function withdraw(uint amount, uint relicId, bool harvest, bool giveEther) external {
        IReliquary _reliquary = IReliquary(reliquary);
        require(_reliquary.isApprovedOrOwner(msg.sender, relicId), "not owner or approved");

        uint pid = _reliquary.getPositionForId(relicId).poolId;
        IERC4626 vault = IERC4626(_reliquary.poolToken(pid));

        if (harvest) {
            _reliquary.withdrawAndHarvest(vault.convertToShares(amount), relicId, msg.sender);
        } else {
            _reliquary.withdraw(vault.convertToShares(amount), relicId);
        }

        if (giveEther) {
            require(vault.asset() == weth, "not an ether vault");
            vault.withdraw(vault.maxWithdraw(address(this)), address(this), address(this));
            IWeth(weth).withdraw(amount);
            payable(msg.sender).sendValue(amount);
        } else {
            vault.withdraw(vault.maxWithdraw(address(this)), msg.sender, address(this));
        }
    }

    /// @notice Owner may send tokens out of this contract since none should be held here. Do not send tokens manually.
    function rescueFunds(address token, address to, uint amount) external onlyOwner {
        if (token == address(0)) {
            payable(to).sendValue(amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    function _prepareDeposit(uint pid, uint amount) internal returns (IERC4626 vault) {
        vault = IERC4626(IReliquary(reliquary).poolToken(pid));
        IERC20 token = IERC20(vault.asset());
        if (msg.value != 0) {
            require(amount == msg.value, "ether amount mismatch");
            require(address(token) == weth, "not an ether vault");
            IWeth(weth).deposit{value: msg.value}();
        } else {
            token.safeTransferFrom(msg.sender, address(this), amount);
        }

        if (token.allowance(address(this), address(vault)) == 0) {
            token.approve(address(vault), type(uint).max);
        }
        vault.deposit(amount, address(this));

        if (vault.allowance(address(this), reliquary) == 0) {
            vault.approve(reliquary, type(uint).max);
        }
    }
}
