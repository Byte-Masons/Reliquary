// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../interfaces/IEmissionCurve.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract OwnableCurve is IEmissionCurve, Ownable {
    uint private rate;

    event LogRate(uint rate);

    constructor(uint _rate) {
        _setRate(_rate);
    }

    function setRate(uint _rate) external onlyOwner {
        _setRate(_rate);
    }

    function getRate(uint) external view override returns (uint) {
        return rate;
    }

    function _setRate(uint _rate) internal {
        require(_rate <= 6e18, "maximum emission rate exceeded");
        rate = _rate;
        emit LogRate(_rate);
    }
}
