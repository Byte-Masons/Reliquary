// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../interfaces/ICurves.sol";

interface IRewarder {
    function onReward(uint256 _relicId, address _to) external;

    function onUpdate(
        ICurves _curve,
        uint256 _relicId,
        uint256 _amount,
        uint256 _oldLevel,
        uint256 _newLevel
    ) external;

    function onDeposit(
        ICurves _curve,
        uint256 _relicId,
        uint256 _depositAmount,
        uint256 _oldAmount,
        uint256 _oldLevel,
        uint256 _newLevel
    ) external;

    function onWithdraw(
        ICurves _curve,
        uint256 _relicId,
        uint256 _withdrawalAmount,
        uint256 _oldAmount,
        uint256 _oldLevel,
        uint256 _newLevel
    ) external;

    function onSplit(
        ICurves _curve,
        uint256 _fromId,
        uint256 _newId,
        uint256 _amount,
        uint256 _fromAmount,
        uint256 _level
    ) external;

    function onShift(
        ICurves _curve,
        uint256 _fromId,
        uint256 _toId,
        uint256 _amount,
        uint256 _oldFromAmount,
        uint256 _oldToAmount,
        uint256 _fromLevel,
        uint256 _oldToLevel,
        uint256 _newToLevel
    ) external;

    function onMerge(
        ICurves _curve,
        uint256 _fromId,
        uint256 _toId,
        uint256 _fromAmount,
        uint256 _toAmount,
        uint256 _fromLevel,
        uint256 _oldToLevel,
        uint256 _newToLevel
    ) external;

    function pendingTokens(uint256 _relicId)
        external
        view
        returns (address[] memory, uint256[] memory);
}
