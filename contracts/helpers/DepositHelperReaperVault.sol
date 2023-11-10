// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IReliquary, PositionInfo} from "../interfaces/IReliquary.sol";

interface IReaperVault is IERC20 {
    function decimals() external view returns (uint8);
    function deposit(uint amount) external;
    function getPricePerFullShare() external view returns (uint);
    function token() external view returns (IERC20);
    function withdrawAll() external;
}

interface IWeth is IERC20 {
    function deposit() external payable;
    function withdraw(uint amount) external;
}

/// @title Helper contract that allows depositing to and withdrawing from Reliquary pools of a Reaper vault in a
/// single transaction using the vault's underlying asset.
contract DepositHelperReaperVault is Ownable {
    using Address for address payable;
    using SafeERC20 for IERC20;

    IReliquary public immutable reliquary;
    IWeth public immutable weth;

    constructor(IReliquary _reliquary, address _weth) {
        reliquary = _reliquary;
        weth = IWeth(_weth);
    }

    receive() external payable {}

    /// @notice Deposit `amount` of ERC20 tokens (or native ether for a supported pool) into existing Relic `relicId`.
    function deposit(uint amount, uint relicId) external payable returns (uint shares) {
        _requireApprovedOrOwner(relicId);
        shares = _prepareDeposit(reliquary.getPositionForId(relicId).poolId, amount);
        reliquary.deposit(shares, relicId);
    }

    /// @notice Send `amount` of ERC20 tokens (or native ether for a supported pool) and create a new Relic in pool `pid`.
    function createRelicAndDeposit(uint pid, uint amount) external payable returns (uint relicId, uint shares) {
        shares = _prepareDeposit(pid, amount);
        relicId = reliquary.createRelicAndDeposit(msg.sender, pid, shares);
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
        _withdraw(amount, relicId, harvest, giveEther);
    }

    /**
     * @notice Withdraw all underlying tokens and rewards from the Relic.
     * @param relicId The NFT ID of the Relic for the position you are withdrawing from.
     * @param giveEther Whether to withdraw the underlying tokens as native ether instead of wrapped.
     * @param burn Whether to burn the empty Relic.
     * Only for supported pools.
     */
    function withdrawAllAndHarvest(uint relicId, bool giveEther, bool burn) external {
        _withdraw(type(uint).max, relicId, true, giveEther);
        if (burn) {
            reliquary.burn(relicId);
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

    function _prepareDeposit(uint pid, uint amount) internal returns (uint shares) {
        IReaperVault vault = IReaperVault(reliquary.poolToken(pid));
        IERC20 token = vault.token();

        if (msg.value != 0) {
            require(amount == msg.value, "ether amount mismatch");
            require(address(token) == address(weth), "not an ether vault");
            weth.deposit{value: msg.value}();
        } else {
            token.safeTransferFrom(msg.sender, address(this), amount);
        }

        if (token.allowance(address(this), address(vault)) == 0) {
            token.approve(address(vault), type(uint).max);
        }

        uint initialShares = vault.balanceOf(address(this));
        vault.deposit(amount);
        shares = vault.balanceOf(address(this)) - initialShares;

        if (vault.allowance(address(this), address(reliquary)) == 0) {
            vault.approve(address(reliquary), type(uint).max);
        }
    }

    function _withdraw(uint amount, uint relicId, bool harvest, bool giveEther) internal {
        _requireApprovedOrOwner(relicId);

        PositionInfo memory position = reliquary.getPositionForId(relicId);
        IReaperVault vault = IReaperVault(reliquary.poolToken(position.poolId));
        uint shares;
        if (amount == type(uint).max) {
            shares = position.amount;
        } else {
            shares = amount * 10 ** vault.decimals() / vault.getPricePerFullShare();
            if (shares > position.amount) {
                require(shares < position.amount + position.amount / 1000, "too much imprecision in share price");
                shares = position.amount;
            }
        }

        if (harvest) {
            reliquary.withdrawAndHarvest(shares, relicId, msg.sender);
        } else {
            reliquary.withdraw(shares, relicId);
        }

        IERC20 token = vault.token();
        uint initialBalance = token.balanceOf(address(this));
        vault.withdrawAll();
        uint balance = token.balanceOf(address(this)) - initialBalance;

        if (giveEther) {
            require(vault.token() == weth, "not an ether vault");
            weth.withdraw(balance);
            payable(msg.sender).sendValue(balance);
        } else {
            vault.token().safeTransfer(msg.sender, balance);
        }
    }

    function _requireApprovedOrOwner(uint relicId) internal view {
        require(reliquary.isApprovedOrOwner(msg.sender, relicId), "not approved or owner");
    }
}
