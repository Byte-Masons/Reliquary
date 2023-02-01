// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./NFTDescriptor.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

contract NFTDescriptorSingle4626 is NFTDescriptor {
    constructor(address _reliquary) NFTDescriptor(_reliquary) {}

    function generateTextFromToken(
        address underlying,
        uint amount,
        string memory //amountString
    ) internal view override returns (string memory text) {
        IERC4626 vault = IERC4626(underlying);
        IERC20Metadata asset = IERC20Metadata(vault.asset());

        string memory assetAmount = generateDecimalString(vault.convertToAssets(amount), asset.decimals());
        text =
            string.concat('<text x="50%" y="300" class="bit" style="font-size: 8">', asset.symbol(), ":", assetAmount);
    }
}
