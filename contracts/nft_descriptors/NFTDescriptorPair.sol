// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./NFTDescriptor.sol";
import "v2-core/interfaces/IUniswapV2Pair.sol";

contract NFTDescriptorPair is NFTDescriptor {
    constructor(address _reliquary) NFTDescriptor(_reliquary) {}

    function generateTextFromToken(
        address _underlying,
        uint256 _amount,
        string memory //_amountString
    ) internal view override returns (string memory text_) {
        IUniswapV2Pair lp_ = IUniswapV2Pair(_underlying);
        IERC20Metadata token0_ = IERC20Metadata(lp_.token0());
        IERC20Metadata token1_ = IERC20Metadata(lp_.token1());

        (uint256 reserves0_, uint256 reserves1_, ) = lp_.getReserves();
        uint256 amount0_ = (_amount * reserves0_) / lp_.totalSupply();
        uint256 amount1_ = (_amount * reserves1_) / lp_.totalSupply();
        text_ = string.concat(
            '<text x="50%" y="300" class="bit" style="font-size: 8">',
            token0_.symbol(),
            ":",
            generateDecimalString(amount0_, token0_.decimals()),
            '</text><text x="50%" y="315" class="bit" style="font-size: 8">',
            token1_.symbol(),
            ":",
            generateDecimalString(amount1_, token1_.decimals())
        );
    }
}
