// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IReliquary} from "../interfaces/IReliquary.sol";

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
        uint minAmountOut;
    }

    function zapIn(Step[] calldata steps, address crypt, uint tokenInAmount) external;
    function zapInETH(Step[] calldata steps, address crypt) external payable;
    function zapOut(Step[] calldata steps, address crypt, uint cryptAmount) external;
    function WETH() external view returns (address);
}

interface IWeth is IERC20 {
    function withdraw(uint amount) external;
}

contract DepositHelperReaperBPT {
    using Address for address payable;
    using SafeERC20 for IERC20;

    address public immutable reliquary;
    address public immutable reZap;
    address public immutable weth;

    constructor(address _reliquary, address _reZap) {
        reliquary = _reliquary;
        reZap = _reZap;
        weth = IReZap(_reZap).WETH();
    }

    receive() external payable {}

    function deposit(IReZap.Step[] calldata steps, uint amount, uint relicId, bool isETH)
        external
        payable
        returns (uint shares)
    {
        IReliquary _reliquary = IReliquary(reliquary);
        require(IReliquary(reliquary).isApprovedOrOwner(msg.sender, relicId), "not owner or approved");

        shares = _prepareDeposit(steps, _reliquary.getPositionForId(relicId).poolId, amount, isETH);
        _reliquary.deposit(shares, relicId);
    }

    function createRelicAndDeposit(IReZap.Step[] calldata steps, uint pid, uint amount, bool isETH)
        external
        payable
        returns (uint relicId, uint shares)
    {
        shares = _prepareDeposit(steps, pid, amount, isETH);
        relicId = IReliquary(reliquary).createRelicAndDeposit(msg.sender, pid, shares);
    }

    function withdraw(IReZap.Step[] calldata steps, uint shares, uint relicId, bool harvest, bool isETH) external {
        address zapOutToken = steps[steps.length - 1].endToken;
        bool isWETH = zapOutToken == weth;
        require(!isETH || isWETH, "invalid steps");
        _prepareWithdrawal(steps, shares, relicId, harvest);

        if (isETH) {
            payable(msg.sender).sendValue(address(this).balance);
        } else {
            uint amountOut = IERC20(zapOutToken).balanceOf(address(this));
            if (isWETH) {
                IWeth(zapOutToken).withdraw(amountOut);
            }
            IERC20(zapOutToken).safeTransfer(msg.sender, amountOut);
        }
    }

    function _prepareDeposit(IReZap.Step[] calldata steps, uint pid, uint amount, bool isETH)
        internal
        returns (uint shares)
    {
        IReaperVault vault = IReaperVault(IReliquary(reliquary).poolToken(pid));
        IReZap _reZap = IReZap(reZap);
        if (isETH) {
            _reZap.zapInETH{value: msg.value}(steps, address(vault));
        } else {
            IERC20 zapInToken = IERC20(steps[0].startToken);
            zapInToken.safeTransferFrom(msg.sender, address(this), amount);

            if (zapInToken.allowance(address(this), address(_reZap)) == 0) {
                zapInToken.approve(address(_reZap), type(uint).max);
            }
            _reZap.zapIn(steps, address(vault), amount);
        }

        shares = vault.balanceOf(address(this));
        if (vault.allowance(address(this), address(reliquary)) == 0) {
            vault.approve(reliquary, type(uint).max);
        }
    }

    function _prepareWithdrawal(IReZap.Step[] calldata steps, uint shares, uint relicId, bool harvest) internal {
        IReliquary _reliquary = IReliquary(reliquary);
        require(IReliquary(reliquary).isApprovedOrOwner(msg.sender, relicId), "not owner or approved");

        uint pid = _reliquary.getPositionForId(relicId).poolId;
        IReaperVault vault = IReaperVault(_reliquary.poolToken(pid));

        if (harvest) {
            _reliquary.withdrawAndHarvest(shares, relicId, msg.sender);
        } else {
            _reliquary.withdraw(shares, relicId);
        }

        IReZap _reZap = IReZap(reZap);
        if (vault.allowance(address(this), address(_reZap)) == 0) {
            vault.approve(address(_reZap), type(uint).max);
        }
        _reZap.zapOut(steps, address(vault), shares);
    }
}
