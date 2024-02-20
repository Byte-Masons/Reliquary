// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./NFTDescriptor.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

contract NFTDescriptorSingle4626 is NFTDescriptor {
    constructor(address _reliquary) NFTDescriptor(_reliquary) {}

    function generateTextFromToken(
        address _underlying,
        uint256 _amount,
        string memory //_amountString
    ) internal view override returns (string memory text_) {
        IERC4626 vault_ = IERC4626(_underlying);
        IERC20Metadata asset_ = IERC20Metadata(vault_.asset());

        string memory assetAmount_ = generateDecimalString(vault_.convertToAssets(_amount), asset_.decimals());
        text_ =
            string.concat('<text x="50%" y="300" class="bit" style="font-size: 8">', asset_.symbol(), ":", assetAmount_);
    }
}
