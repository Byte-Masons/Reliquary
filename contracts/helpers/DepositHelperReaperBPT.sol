// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IReliquary, PositionInfo} from "../interfaces/IReliquary.sol";

interface IReaperVault is IERC20 {
    function token() external view returns (IERC20);
}

interface IReZap {
    enum JoinType {
        Swap,
        Weighted
    }

    struct Step {
        address startToken;
        address endToken;
        uint8 inIdx;
        uint8 outIdx;
        JoinType jT;
        bytes32 poolId;
        uint256 minAmountOut;
    }

    function zapIn(Step[] calldata steps, address crypt, uint256 tokenInAmount) external;

    function zapInETH(Step[] calldata steps, address crypt) external payable;

    function zapOut(Step[] calldata steps, address crypt, uint256 cryptAmount) external;

    function WETH() external view returns (address);
}

interface IWeth is IERC20 {
    function deposit() external payable;
}

/**
 *  @title Helper contract that allows depositing to and withdrawing from Reliquary pools of a Reaper vault (or possibly
 *  similar) for a Balancer Pool Token in a single transaction using one of the BPT's underlying assets.
 *  @notice Due to the complexities and risks associated with inputting the `Step` struct arrays in each function,
 *  THIS CONTRACT SHOULD NOT BE WRITTEN TO USING A BLOCK EXPLORER.
 */
contract DepositHelperReaperBPT is Ownable {
    using Address for address payable;
    using SafeERC20 for IERC20;

    IReliquary public immutable reliquary;
    IReZap public immutable reZap;
    IWeth public immutable weth;

    constructor(IReliquary _reliquary, IReZap _reZap) {
        reliquary = _reliquary;
        reZap = _reZap;
        weth = IWeth(_reZap.WETH());
    }

    receive() external payable {}

    function deposit(IReZap.Step[] calldata _steps, uint256 _amount, uint256 _relicId)
        external
        payable
        returns (uint256 shares_)
    {
        _requireApprovedOrOwner(_relicId);

        shares_ = _prepareDeposit(_steps, reliquary.getPositionForId(_relicId).poolId, _amount);
        reliquary.deposit(shares_, _relicId);
    }

    function createRelicAndDeposit(IReZap.Step[] calldata _steps, uint256 _pid, uint256 _amount)
        external
        payable
        returns (uint256 relicId_, uint256 shares_)
    {
        shares_ = _prepareDeposit(_steps, _pid, _amount);
        relicId_ = reliquary.createRelicAndDeposit(msg.sender, _pid, shares_);
    }

    function withdraw(
        IReZap.Step[] calldata _steps,
        uint256 _shares,
        uint256 _relicId,
        bool _harvest,
        bool _giveEther
    ) external {
        (, IReaperVault vault) = _prepareWithdrawal(_steps, _relicId, _giveEther);
        if (_giveEther) {
            _withdrawEther(vault, _steps, _shares, _relicId, _harvest);
        } else {
            _withdrawERC20(vault, _steps, _shares, _relicId, _harvest);
        }
    }

    function withdrawAllAndHarvest(
        IReZap.Step[] calldata _steps,
        uint256 _relicId,
        bool _giveEther,
        bool _burn
    ) external {
        (PositionInfo memory position, IReaperVault vault) =
            _prepareWithdrawal(_steps, _relicId, _giveEther);
        if (_giveEther) {
            _withdrawEther(vault, _steps, position.amount, _relicId, true);
        } else {
            _withdrawERC20(vault, _steps, position.amount, _relicId, true);
        }
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

    function _prepareDeposit(IReZap.Step[] calldata _steps, uint256 _pid, uint256 _amount)
        internal
        returns (uint256 shares_)
    {
        IReaperVault vault_ = IReaperVault(reliquary.getPoolInfo(_pid).poolToken);
        uint256 initialShares_ = vault_.balanceOf(address(this));
        if (msg.value != 0) {
            reZap.zapInETH{value: msg.value}(_steps, address(vault_));
        } else {
            IERC20 zapInToken = IERC20(_steps[0].startToken);
            zapInToken.safeTransferFrom(msg.sender, address(this), _amount);

            if (zapInToken.allowance(address(this), address(reZap)) == 0) {
                zapInToken.approve(address(reZap), type(uint256).max);
            }
            reZap.zapIn(_steps, address(vault_), _amount);
        }

        shares_ = vault_.balanceOf(address(this)) - initialShares_;
        if (vault_.allowance(address(this), address(reliquary)) == 0) {
            vault_.approve(address(reliquary), type(uint256).max);
        }
    }

    function _prepareWithdrawal(IReZap.Step[] calldata _steps, uint256 _relicId, bool _giveEther)
        internal
        view
        returns (PositionInfo memory position, IReaperVault vault)
    {
        address zapOutToken_ = _steps[_steps.length - 1].endToken;
        if (_giveEther) {
            require(zapOutToken_ == address(weth), "invalid steps");
        }

        _requireApprovedOrOwner(_relicId);

        position = reliquary.getPositionForId(_relicId);
        vault = IReaperVault(reliquary.getPoolInfo(position.poolId).poolToken);
    }

    function _withdrawERC20(
        IReaperVault vault,
        IReZap.Step[] calldata _steps,
        uint256 _shares,
        uint256 _relicId,
        bool _harvest
    ) internal {
        _withdrawFromRelicAndApproveVault(vault, _shares, _relicId, _harvest);

        address zapOutToken_ = _steps[_steps.length - 1].endToken;
        uint256 initialTokenBalance_ = IERC20(zapOutToken_).balanceOf(address(this));
        uint256 initialEtherBalance_ = address(this).balance;
        reZap.zapOut(_steps, address(vault), _shares);

        uint256 amountOut_;
        if (zapOutToken_ == address(weth)) {
            amountOut_ = address(this).balance - initialEtherBalance_;
            IWeth(zapOutToken_).deposit{value: amountOut_}();
        } else {
            amountOut_ = IERC20(zapOutToken_).balanceOf(address(this)) - initialTokenBalance_;
        }
        IERC20(zapOutToken_).safeTransfer(msg.sender, amountOut_);
    }

    function _withdrawEther(
        IReaperVault _vault,
        IReZap.Step[] calldata _steps,
        uint256 _shares,
        uint256 _relicId,
        bool _harvest
    ) internal {
        _withdrawFromRelicAndApproveVault(_vault, _shares, _relicId, _harvest);

        uint256 initialEtherBalance_ = address(this).balance;
        reZap.zapOut(_steps, address(_vault), _shares);

        payable(msg.sender).sendValue(address(this).balance - initialEtherBalance_);
    }

    function _withdrawFromRelicAndApproveVault(
        IReaperVault _vault,
        uint256 _shares,
        uint256 _relicId,
        bool _harvest
    ) internal {
        if (_harvest) {
            reliquary.withdrawAndHarvest(_shares, _relicId, msg.sender);
        } else {
            reliquary.withdraw(_shares, _relicId);
        }

        if (_vault.allowance(address(this), address(reZap)) == 0) {
            _vault.approve(address(reZap), type(uint256).max);
        }
    }

    function _requireApprovedOrOwner(uint256 _relicId) internal view {
        require(reliquary.isApprovedOrOwner(msg.sender, _relicId), "not approved or owner");
    }
}
