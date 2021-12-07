pragma solidity ^0.8.0;

library EighthRoot {

  function _curve(uint maturity) internal returns (uint) {
    uint juniorCurve = sqrt(maturity / 4) / 5;
    uint seniorCurve = sqrt(Math.sqrt(maturity)) / 2;

    return min(juniorCurve, seniorCurve);
  }

  function min(uint x, uint y) internal pure returns (uint z) {
      z = x < y ? x : y;
  }

  // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
  function sqrt(uint y) internal pure returns (uint z) {
      if (y > 3) {
          z = y;
          uint x = y / 2 + 1;
          while (x < z) {
              z = x;
              x = (y / x + x) / 2;
          }
      } else if (y != 0) {
          z = 1;
      }
  }

}