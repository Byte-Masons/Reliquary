// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IVoter.sol";
import "../interfaces/IReliquary.sol";

library ReliquaryLogic {

    
    /**
     * @notice Used in `_updateEntry` to find weights without any underflows or zero division problems.
     * @param addedValue New value being added.
     * @param oldValue Current amount of x.
     */
    function _findWeight(uint addedValue, uint oldValue) public pure returns (uint weightNew) {
        if (oldValue < addedValue) {
            weightNew = 1e12 - oldValue * 1e12 / (addedValue + oldValue);
        } else if (addedValue < oldValue) {
            weightNew = addedValue * 1e12 / (addedValue + oldValue);
        } else {
            weightNew = 5e11;
        }
    }

    /// @dev Handle updating balances for each affected tranche when shifting and merging.

    struct shiftBalancesVars {
        uint fromLevel;
        uint oldToLevel;
        uint newToLevel;
        uint poolId;
        uint amount;
        uint toAmount;
        uint newToAmount;
    }

    function _shiftLevelBalances(
        shiftBalancesVars memory vars,
        LevelInfo[] storage levels
    ) public {
        if (vars.fromLevel != vars.newToLevel) {
            levels[vars.poolId].balance[vars.fromLevel] -= vars.amount;
        }
        if (vars.oldToLevel != vars.newToLevel) {
            levels[vars.poolId].balance[vars.oldToLevel] -= vars.toAmount;
        }
        if (vars.fromLevel != vars.newToLevel && vars.oldToLevel != vars.newToLevel) {
            levels[vars.poolId].balance[vars.newToLevel] += vars.newToAmount;
        } else if (vars.fromLevel != vars.newToLevel) {
            levels[vars.poolId].balance[vars.newToLevel] += vars.amount;
        } else if (vars.oldToLevel != vars.newToLevel) {
            levels[vars.poolId].balance[vars.newToLevel] += vars.toAmount;
        }
    }

    /**
     * @notice View function to see level of position if it were to be updated.
     * @param relicId ID of the position.
     * @return level Level for given position upon update.
     */
    function levelOnUpdate(
        uint relicId,
        mapping(uint256 => PositionInfo) storage positionForId,
        LevelInfo[] storage levels
    ) public view returns (uint level) {
        PositionInfo storage position = positionForId[relicId];
        LevelInfo storage levelInfo = levels[position.poolId];
        uint length = levelInfo.requiredMaturities.length;
        if (length == 1) {
            return 0;
        }

        uint maturity = block.timestamp - position.entry;
        for (level = length - 1; true;) {
            if (maturity >= levelInfo.requiredMaturities[level]) {
                break;
            }
            unchecked {
                --level;
            }
        }
    }

        /**
     * @notice Updates the user's entry time based on the weight of their deposit or withdrawal.
     * @param amount The amount of the deposit / withdrawal.
     * @param relicId The NFT ID of the position being updated.
     */
    function _updateEntry(
        uint amount, 
        uint relicId,
        mapping(uint => PositionInfo) storage positionForId
     ) public {
        PositionInfo storage position = positionForId[relicId];
        uint amountBefore = position.amount;
        if (amountBefore == 0) {
            position.entry = block.timestamp;
        } else {
            uint weight = _findWeight(amount, amountBefore);
            uint entryBefore = position.entry;
            uint maturity = block.timestamp - entryBefore;
            position.entry = entryBefore + maturity * weight / 1e12;
        }
    }

    /**
     * @notice Updates the position's level based on entry time.
     * @param relicId The NFT ID of the position being updated.
     * @param oldLevel Level of position before update.
     * @return newLevel Level of position after update.
     */
    function _updateLevel(
        uint relicId,
        uint oldLevel,
        mapping(uint => PositionInfo) storage positionForId,
        LevelInfo[] storage levels
        ) external returns (uint newLevel) {
        newLevel = levelOnUpdate(relicId, positionForId, levels);
        PositionInfo storage position = positionForId[relicId];
        if (oldLevel != newLevel) {
            position.level = newLevel;
            //emit ReliquaryEvents.LevelChanged(relicId, newLevel);
        }
    }


}