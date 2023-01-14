// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
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

    address public immutable reliquary;
    address public immutable reZap;
    address public immutable weth;

    constructor(address _reliquary, address _reZap) {
        reliquary = _reliquary;
        reZap = _reZap;
        weth = IReZap(_reZap).WETH();
    }

    receive() external payable {}

    function deposit(IReZap.Step[] calldata steps, uint amount, uint relicId) external payable returns (uint shares) {
        IReliquary _reliquary = IReliquary(reliquary);
        require(_reliquary.isApprovedOrOwner(msg.sender, relicId), "not owner or approved");

        shares = _prepareDeposit(steps, _reliquary.getPositionForId(relicId).poolId, amount);
        _reliquary.deposit(shares, relicId);
    }

    function createRelicAndDeposit(IReZap.Step[] calldata steps, uint pid, uint amount)
        external
        payable
        returns (uint relicId, uint shares)
    {
        shares = _prepareDeposit(steps, pid, amount);
        relicId = IReliquary(reliquary).createRelicAndDeposit(msg.sender, pid, shares);
    }

    function withdraw(IReZap.Step[] calldata steps, uint shares, uint relicId, bool harvest, bool giveEther) external {
        address zapOutToken = steps[steps.length - 1].endToken;
        bool isWETH = zapOutToken == weth;
        require(!giveEther || isWETH, "invalid steps");
        _prepareWithdrawal(steps, shares, relicId, harvest);

        if (giveEther) {
            payable(msg.sender).sendValue(address(this).balance);
        } else {
            uint amountOut;
            if (isWETH) {
                amountOut = address(this).balance;
                IWeth(zapOutToken).deposit{value: amountOut}();
            } else {
                amountOut = IERC20(zapOutToken).balanceOf(address(this));
            }
            IERC20(zapOutToken).safeTransfer(msg.sender, amountOut);
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

    function _prepareDeposit(IReZap.Step[] calldata steps, uint pid, uint amount) internal returns (uint shares) {
        IReaperVault vault = IReaperVault(IReliquary(reliquary).poolToken(pid));
        IReZap _reZap = IReZap(reZap);
        if (msg.value != 0) {
            _reZap.zapInETH{value: msg.value}(steps, address(vault));
        } else {
            IERC20 zapInToken = IERC20(steps[0].startToken);
            zapInToken.safeTransferFrom(msg.sender, address(this), amount);

            if (zapInToken.allowance(address(this), reZap) == 0) {
                zapInToken.approve(reZap, type(uint).max);
            }
            _reZap.zapIn(steps, address(vault), amount);
        }

        shares = vault.balanceOf(address(this));
        if (vault.allowance(address(this), reliquary) == 0) {
            vault.approve(reliquary, type(uint).max);
        }
    }

    function _prepareWithdrawal(IReZap.Step[] calldata steps, uint shares, uint relicId, bool harvest) internal {
        IReliquary _reliquary = IReliquary(reliquary);
        require(_reliquary.isApprovedOrOwner(msg.sender, relicId), "not owner or approved");

        uint pid = _reliquary.getPositionForId(relicId).poolId;
        IReaperVault vault = IReaperVault(_reliquary.poolToken(pid));

        if (harvest) {
            _reliquary.withdrawAndHarvest(shares, relicId, msg.sender);
        } else {
            _reliquary.withdraw(shares, relicId);
        }

        if (vault.allowance(address(this), reZap) == 0) {
            vault.approve(reZap, type(uint).max);
        }
        IReZap(reZap).zapOut(steps, address(vault), shares);
    }
}
