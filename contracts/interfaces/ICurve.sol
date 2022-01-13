pragma solidity ^0.8.0;

interface ICurve {
    function curve(uint256 maturity) external pure returns (uint256);
}
