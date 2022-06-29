// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import './NFTDescriptor.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

contract NFTDescriptorPair is NFTDescriptor {
    constructor(IReliquary _reliquary) NFTDescriptor(_reliquary) {}

    function generateTextFromToken(
        address underlying,
        uint amount,
	string memory amountString
    ) internal view override returns (string memory tags) {
        IUniswapV2Pair lp = IUniswapV2Pair(underlying);
        IERC20Values token0 = IERC20Values(lp.token0());
        IERC20Values token1 = IERC20Values(lp.token1());

        (uint reserves0, uint reserves1, ) = lp.getReserves();
        uint amount0 = amount * reserves0 / lp.totalSupply();
        uint amount1 = amount * reserves1 / lp.totalSupply();
        tags = string.concat(
            '<text x="50%" y="320" class="bit" style="font-size: 8">', token0.symbol(), ':', generateDecimalString(amount0, token0.decimals()),
            '</text><text x="50%" y="340" class="bit" style="font-size: 8">', token1.symbol(), ':', generateDecimalString(amount1, token1.decimals())
        );
    }
}
