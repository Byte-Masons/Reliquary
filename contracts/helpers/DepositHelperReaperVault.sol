// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IReliquary, PositionInfo} from "../interfaces/IReliquary.sol";

interface IReaperVault is IERC20 {
    function decimals() external view returns (uint8);

    function deposit(uint256 amount) external;

    function getPricePerFullShare() external view returns (uint256);

    function token() external view returns (IERC20);

    function withdrawAll() external;
}

interface IWeth is IERC20 {
    function deposit() external payable;

    function withdraw(uint256 amount) external;
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

    /// @notice Deposit `_amount` of ERC20 tokens (or native ether for a supported pool) into existing Relic `_relicId`.
    function deposit(uint256 _amount, uint256 _relicId) external payable returns (uint256 shares_) {
        _requireApprovedOrOwner(_relicId);
        shares_ = _prepareDeposit(reliquary.getPositionForId(_relicId).poolId, _amount);
        reliquary.deposit(shares_, _relicId);
    }

    /// @notice Send `_amount` of ERC20 tokens (or native ether for a supported pool) and create a new Relic in pool `_pid`.
    function createRelicAndDeposit(
        uint256 _pid,
        uint256 _amount
    ) external payable returns (uint256 relicId_, uint256 shares_) {
        shares_ = _prepareDeposit(_pid, _amount);
        relicId_ = reliquary.createRelicAndDeposit(msg.sender, _pid, shares_);
    }

    /**
     * @notice Withdraw underlying tokens from the Relic.
     * @param _amount Amount of underlying token to withdraw.
     * @param _relicId The NFT ID of the Relic for the position you are withdrawing from.
     * @param _harvest Whether to also harvest pending rewards to `msg.sender`.
     * @param _giveEther Whether to withdraw the underlying tokens as native ether instead of wrapped.
     * Only for supported pools.
     */
    function withdraw(uint256 _amount, uint256 _relicId, bool _harvest, bool _giveEther) external {
        _withdraw(_amount, _relicId, _harvest, _giveEther);
    }

    /**
     * @notice Withdraw all underlying tokens and rewards from the Relic.
     * @param _relicId The NFT ID of the Relic for the position you are withdrawing from.
     * @param _giveEther Whether to withdraw the underlying tokens as native ether instead of wrapped.
     * @param _burn Whether to burn the empty Relic.
     * Only for supported pools.
     */
    function withdrawAllAndHarvest(uint256 _relicId, bool _giveEther, bool _burn) external {
        _withdraw(type(uint256).max, _relicId, true, _giveEther);
        if (_burn) {
            reliquary.burn(_relicId);
        }
    }

    /// @notice Owner may send tokens out of this contract since none should be held here. Do not send tokens manually.
    function rescueFunds(address _token, address _to, uint256 _amount) external onlyOwner {
        if (_token == address(0)) {
            payable(_to).sendValue(_amount);
        } else {
            IERC20(_token).safeTransfer(_to, _amount);
        }
    }

    function _prepareDeposit(uint256 _pid, uint256 _amount) internal returns (uint256 shares_) {
        IReaperVault vault_ = IReaperVault(reliquary.getPoolInfo(_pid).poolToken);
        IERC20 token_ = vault_.token();

        if (msg.value != 0) {
            require(_amount == msg.value, "ether amount mismatch");
            require(address(token_) == address(weth), "not an ether vault");
            weth.deposit{value: msg.value}();
        } else {
            token_.safeTransferFrom(msg.sender, address(this), _amount);
        }

        if (token_.allowance(address(this), address(vault_)) == 0) {
            token_.approve(address(vault_), type(uint256).max);
        }

        uint256 initialShares_ = vault_.balanceOf(address(this));
        vault_.deposit(_amount);
        shares_ = vault_.balanceOf(address(this)) - initialShares_;

        if (vault_.allowance(address(this), address(reliquary)) == 0) {
            vault_.approve(address(reliquary), type(uint256).max);
        }
    }

    function _withdraw(uint256 _amount, uint256 _relicId, bool _harvest, bool _giveEther) internal {
        _requireApprovedOrOwner(_relicId);

        PositionInfo memory position_ = reliquary.getPositionForId(_relicId);
        IReaperVault vault_ = IReaperVault(reliquary.getPoolInfo(position_.poolId).poolToken);
        uint256 shares_;
        if (_amount == type(uint256).max) {
            shares_ = position_.amount;
        } else {
            shares_ = (_amount * 10 ** vault_.decimals()) / vault_.getPricePerFullShare();
            if (shares_ > position_.amount) {
                require(
                    shares_ < position_.amount + position_.amount / 1000,
                    "too much imprecision in share price"
                );
                shares_ = position_.amount;
            }
        }

        if (_harvest) {
            reliquary.withdrawAndHarvest(shares_, _relicId, msg.sender);
        } else {
            reliquary.withdraw(shares_, _relicId);
        }

        IERC20 token_ = vault_.token();
        uint256 initialBalance_ = token_.balanceOf(address(this));
        vault_.withdrawAll();
        uint256 balance_ = token_.balanceOf(address(this)) - initialBalance_;

        if (_giveEther) {
            require(vault_.token() == weth, "not an ether vault");
            weth.withdraw(balance_);
            payable(msg.sender).sendValue(balance_);
        } else {
            vault_.token().safeTransfer(msg.sender, balance_);
        }
    }

    function _requireApprovedOrOwner(uint256 _relicId) internal view {
        require(reliquary.isApprovedOrOwner(msg.sender, _relicId), "not approved or owner");
    }
}
