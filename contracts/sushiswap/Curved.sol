pragma solidity ^0.8.0;

import "./Reliquary.sol";
import "./ICurve.sol";

interface ICurve {

  function curve(uint) external virtual returns (uint);

}

/*
 + @title The Byte Masons' Reliquary
 + @author Justin Bebis & the Byte Masons
 + @notice This contract will curve MasterChefV2 emissions while maintaing the linear distribution
 + @param "maturity" is used to describe the amount of time someone has been in the pool
 + @dev you can create arbitrary curves and point at them by updating the curveAddress in poolInfo
*/
contract Reliquary is MasterChefV2 {

  // @notice used to determine whether a user is above or below the average curve
  enum Placement { ABOVE, BELOW }

  /*
   + @notice used to determine user's emission modifier
   + @param distance the % distance the user is from the curve, in base 10000
   + @param placement flag to note whether user is above or below the average maturity
  */

  struct Position {
    uint distance;
    Placement placement;
  }

  uint256 private constant CURVE_PRECISION = 1e18;

  /*
   + @notice pulls MasterChef data and passes it to the curve library
   + @param userAddress generally msg.sender - the user whose position on the maturity curve you'd like to see
   +
  */

  function curve(uint userAddress, uint pid) public view returns (uint) {
    UserInfo memory user = userInfo[pid][msg.sender];

    uint maturity = block.timestamp - user.entryTime;

    return ICurve(poolInfo[pid].curveAddress)._curve(maturity);
  }

  /*
   +
   +
   +
  */

  function _curve(uint maturity) internal returns (uint) {
    uint juniorCurve = Math.sqrt(maturity / 4) / 5;
    uint seniorCurve = Math.sqrt(Math.sqrt(maturity)) / 2;

    return Math.min(juniorCurve, seniorCurve);
  }

  /*
   +
   +
   +
  */

  function modifyEmissions(uint amount, address user, uint8 pid) internal returns (uint) {
    Position position = calculateDistanceFromMean(user, pid);

    if (position.placement == Placement.ABOVE) {
      return amount * (BASIS_POINTS + position.distance) / BASIS_POINTS;
    } else if (position.placement == Placement.BELOW) {
      return amount * (BASIS_POINTS - position.distance) / BASIS_POINTS;
    } else {
      return amount;
    }
  }

  /*
   +
   +
   +
  */

  function calculateDistanceFromMean(address user, uint8 pid) public view returns (Position memory) {
    uint position = curve(user, pid);
    uint mean = calculateMean(pid);

    if (position < mean) {
      return Position((mean - position)*BASIS_POINTS/mean, Placement.BELOW);
    } else if (mean < position) {
      return Position((position - mean)*BASIS_POINTS/mean, Placement.ABOVE);
    } else {
      return Position(0);
    }
  }

  /*
   +
   +
   +
  */

  function calculateMean(uint pid) internal returns (uint) {
    PoolInfo memory pool = poolInfo[pid];
    uint protocolMaturity = block.timestamp - averageEntry;
    return _curve(maturity);
  }

  /*
   +
   +
   +
  */

  function calculateWeight(uint pid, uint depositAmount) internal returns (uint) {
    return depositAmount * CURVE_PRECISION / totalDeposits(pid);
  }

  /*
   +
   +
   +
  */

  function calculateDistanceFromMean(address user, uint8 pid) public view returns (uint) {
    uint position = curve(user, pid)
  }

  /*
   +
   +
   +
  */

  function _updateAverageEntry(uint pid, uint weight) internal returns (bool) {

    uint avgTimestamp = poolInfo[pid].averageEntry;
    uint diff = block.timestamp - avgTimestamp;
    uint weightedDiff = diff * weight / 1e18;
    poolInfo[pid].averageEntry += weightedDiff;
    return true;
  }

  function _updateEntryTime(uint _amount, uint positionId) internal returns (bool) {
    PositionInfo storage position = positionInfo[pid][positionId];
    uint amountPercent = amount * BASIS_POINTS / position.amount;
    uint maturity = block.timestamp - position.entryTime;
    position.entryTime += (maturity * amountPercent / BASIS_POINTS);
    return true;
  }

  /*
   +
   +
   +
  */

  function _calculateWeight(uint pid, uint depositAmount) internal view returns (uint) {
    return depositAmount * CURVE_PRECISION / totalDeposits(pid);
  }

  /*
   +
   +
   +
  */

  function totalDeposits(uint8 pid) public view returns (uint256) {
    return IERC20(lpToken[pid]).balanceOf(address(this));
  }

}
