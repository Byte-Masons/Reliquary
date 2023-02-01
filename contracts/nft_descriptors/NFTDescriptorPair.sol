// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./NFTDescriptor.sol";
import "v2-core/interfaces/IUniswapV2Pair.sol";

contract NFTDescriptorPair is NFTDescriptor {
    constructor(address _reliquary) NFTDescriptor(_reliquary) {}

    function generateTextFromToken(
        address underlying,
        uint amount,
        string memory //amountString
    ) internal view override returns (string memory text) {
        IUniswapV2Pair lp = IUniswapV2Pair(underlying);
        IERC20Metadata token0 = IERC20Metadata(lp.token0());
        IERC20Metadata token1 = IERC20Metadata(lp.token1());

        (uint reserves0, uint reserves1,) = lp.getReserves();
        uint amount0 = amount * reserves0 / lp.totalSupply();
        uint amount1 = amount * reserves1 / lp.totalSupply();
        text = string.concat(
            '<text x="50%" y="300" class="bit" style="font-size: 8">',
            token0.symbol(),
            ":",
            generateDecimalString(amount0, token0.decimals()),
            '</text><text x="50%" y="315" class="bit" style="font-size: 8">',
            token1.symbol(),
            ":",
            generateDecimalString(amount1, token1.decimals())
        );
    }
}
