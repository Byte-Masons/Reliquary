// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IReliquary} from "../interfaces/IReliquary.sol";

interface IReaperVault is IERC20 {
    function deposit(uint amount) external;
    function withdraw(uint shares) external;
    function balance() external view returns (uint);
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
    function zapOut(Step[] calldata steps, address crypt, uint cryptAmount) external;
    function WETH() external view returns (address);
}

contract DepositHelperReaperBPT {
    using Address for address payable;
    using SafeERC20 for IERC20;

    address public immutable reliquary;
    address public immutable rewardToken;
    address public immutable reZap;
    address public immutable weth;

    constructor(address _reliquary, address _reZap) {
        reliquary = _reliquary;
        rewardToken = IReliquary(_reliquary).rewardToken();
        reZap = _reZap;
        weth = IReZap(_reZap).WETH();
    }

    receive() external payable {}

    function deposit(IReZap.Step[] calldata steps, uint amount, uint relicId) external returns (uint shares) {
        IReliquary _reliquary = IReliquary(reliquary);
        require(_reliquary.isApprovedOrOwner(msg.sender, relicId), "not owner or approved");

        IReaperVault vault = _prepareDeposit(steps, _reliquary.getPositionForId(relicId).poolId, amount);
        shares = vault.balanceOf(address(this));
        _reliquary.deposit(shares, relicId);
    }

    function createRelicAndDeposit(IReZap.Step[] calldata steps, uint pid, uint amount)
        external
        returns (uint relicId, uint shares)
    {
        IReaperVault vault = _prepareDeposit(steps, pid, amount);
        shares = vault.balanceOf(address(this));
        relicId = IReliquary(reliquary).createRelicAndDeposit(msg.sender, pid, shares);
    }

    function withdraw(IReZap.Step[] calldata steps, uint shares, uint relicId, bool harvest) external {
        IReliquary _reliquary = IReliquary(reliquary);
        require(_reliquary.isApprovedOrOwner(msg.sender, relicId), "not owner or approved");

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

        IERC20 zapOutToken = IERC20(steps[steps.length - 1].endToken);
        if (address(zapOutToken) == weth) {
            payable(msg.sender).sendValue(address(this).balance);
        } else {
            zapOutToken.safeTransfer(msg.sender, zapOutToken.balanceOf(address(this)));
        }
    }

    function _prepareDeposit(IReZap.Step[] calldata steps, uint pid, uint amount)
        internal
        returns (IReaperVault vault)
    {
        vault = IReaperVault(IReliquary(reliquary).poolToken(pid));
        IERC20 zapInToken = IERC20(steps[0].startToken);
        zapInToken.safeTransferFrom(msg.sender, address(this), amount);

        IReZap _reZap = IReZap(reZap);
        if (zapInToken.allowance(address(this), address(_reZap)) == 0) {
            zapInToken.approve(address(_reZap), type(uint).max);
        }
        IReZap(reZap).zapIn(steps, address(vault), amount);

        if (vault.allowance(address(this), address(reliquary)) == 0) {
            vault.approve(reliquary, type(uint).max);
        }
    }
}
