// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IReliquary, PositionInfo} from "../interfaces/IReliquary.sol";

interface IWeth is IERC20 {
    function deposit() external payable;
    function withdraw(uint amount) external;
}

/// @title Helper contract that allows depositing to and withdrawing from Reliquary pools of an ERC4626 vault in a
/// single transaction using the vault's underlying asset.
contract DepositHelperERC4626 is Ownable {
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
    function deposit(uint amount, uint relicId) external payable {
        require(reliquary.isApprovedOrOwner(msg.sender, relicId), "not owner or approved");

        uint shares = _prepareDeposit(reliquary.getPositionForId(relicId).poolId, amount);
        reliquary.deposit(shares, relicId);
    }

    /// @notice Send `amount` of ERC20 tokens (or native ether for a supported pool) and create a new Relic in pool `pid`.
    function createRelicAndDeposit(uint pid, uint amount) external payable returns (uint relicId) {
        uint shares = _prepareDeposit(pid, amount);
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
        (, IERC4626 vault) = _prepareWithdrawal(relicId);
        _withdraw(vault, vault.convertToShares(amount), relicId, harvest, giveEther);
    }

    /**
     * @notice Withdraw all underlying tokens and rewards from the Relic.
     * @param relicId The NFT ID of the Relic for the position you are withdrawing from.
     * @param giveEther Whether to withdraw the underlying tokens as native ether instead of wrapped.
     * @param burn Whether to burn the empty Relic.
     * Only for supported pools.
     */
    function withdrawAllAndHarvest(uint relicId, bool giveEther, bool burn) external {
        (PositionInfo memory position, IERC4626 vault) = _prepareWithdrawal(relicId);
        _withdraw(vault, position.amount, relicId, true, giveEther);
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
        IERC4626 vault = IERC4626(reliquary.poolToken(pid));
        IERC20 token = IERC20(vault.asset());
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
        shares = vault.deposit(amount, address(this));

        if (vault.allowance(address(this), address(reliquary)) == 0) {
            vault.approve(address(reliquary), type(uint).max);
        }
    }

    function _prepareWithdrawal(uint relicId) internal view returns (PositionInfo memory position, IERC4626 vault) {
        require(reliquary.isApprovedOrOwner(msg.sender, relicId), "not owner or approved");

        position = reliquary.getPositionForId(relicId);
        vault = IERC4626(reliquary.poolToken(position.poolId));
    }

    function _withdraw(IERC4626 vault, uint amount, uint relicId, bool harvest, bool giveEther) internal {
        if (harvest) {
            reliquary.withdrawAndHarvest(amount, relicId, msg.sender);
        } else {
            reliquary.withdraw(amount, relicId);
        }

        if (giveEther) {
            require(vault.asset() == address(weth), "not an ether vault");
            uint amountETH = vault.maxWithdraw(address(this));
            vault.withdraw(amountETH, address(this), address(this));
            weth.withdraw(amountETH);
            payable(msg.sender).sendValue(amountETH);
        } else {
            vault.withdraw(vault.maxWithdraw(address(this)), msg.sender, address(this));
        }
    }
}
