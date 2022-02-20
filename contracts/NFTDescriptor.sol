// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import '@openzeppelin/contracts/utils/Strings.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import 'base64-sol/base64.sol';
import './interfaces/ICurve.sol';

interface IERC20Values {
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

contract NFTDescriptor {
    using Strings for uint256;

    uint256 private constant NUM_BARS = 20;
    uint256 private constant GRAPH_WIDTH = 190;
    uint256 private constant GRAPH_HEIGHT = 150;
    uint256 private constant BAR_WIDTH = GRAPH_WIDTH / NUM_BARS;
    // testing account, not ipfs to be used in production
    string private constant IPFS = 'https://gateway.pinata.cloud/ipfs/QmbYvNccKU3e2LFGnTDHa2asxQat2Ldw1G2wZ4iNzr59no/';

    struct ConstructTokenURIParams {
        uint256 tokenId;
        bool isLP;
        address underlyingAddress;
        uint256 poolId;
        uint256 amount;
        uint256 pendingOath;
        uint256 maturity;
        address curveAddress;
    }

    function constructTokenURI(ConstructTokenURIParams memory params) public view returns (string memory) {
        string memory tokenId = params.tokenId.toString();
        string memory poolId = params.poolId.toString();
        string memory pendingOath = generateDecimalString(params.pendingOath, 18);
        uint256 currentMultiplier = ICurve(params.curveAddress).curve(params.maturity) + 1;

        (string memory underlying, string memory amount, string memory tags) = generateTextFromToken(
            params.underlyingAddress,
            params.isLP,
            params.amount
        );
        string memory name = string(
            abi.encodePacked(
                'Relic #', tokenId, ': ', underlying
            )
        );
        string memory description =
            generateDescription(
                underlying,
                poolId,
                amount,
                pendingOath,
                params.maturity,
                currentMultiplier
            );
        address curveAddress = params.curveAddress;
        uint256 maturity = params.maturity;
        string memory image =
            Base64.encode(
                bytes(
                    string(
                        abi.encodePacked(
                            generateSVGImage(
                                tokenId,
                                tags,
                                pendingOath,
                                maturity,
                                currentMultiplier
                            ),
                            generateBars(
                                curveAddress,
                                maturity,
                                currentMultiplier
                            )
                        )
                    )
                )
            );

        return
            string(
                abi.encodePacked(
                    'data:application/json;base64,',
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"',
                                name,
                                '", "description":"',
                                description,
                                '", "image": "',
                                'data:image/svg+xml;base64,',
                                image,
                                '"}'
                            )
                        )
                    )
                )
            );
    }

    function generateDescription(
        string memory underlying,
        string memory poolId,
        string memory amount,
        string memory pendingOath,
        uint256 maturity,
        uint256 currentMultiplier
    ) internal pure returns (string memory) {
        return
        string(
            abi.encodePacked(
                'This NFT represents a liquidity position in a Reliquary ',
                underlying,
                ' pool. ',
                'The owner of this NFT can modify or redeem the position.\\n',
                '\\nPool ID: ',
                poolId,
                '\\nAmount Deposited: ',
                amount,
                '\\nPending Oath: ',
                pendingOath,
                '\\nMaturity: ',
                maturity.toString(),
                '\\nCurrent Reward Multiplier: ',
                currentMultiplier.toString()
            )
        );
    }

    function generateSVGImage(
        string memory tokenId,
        string memory tags,
        string memory pendingOath,
        uint256 maturity,
        uint256 currentMultiplier
    ) internal pure returns (string memory svg) {
        uint256 level = currentMultiplier >= 80 ? 5 : currentMultiplier / 20 + 1;
        svg = string(
            abi.encodePacked(
                '<svg width="290" height="450" viewBox="0 0 290 450" style="background-color:#131313" xmlns="http://www.w3.org/2000/svg">',
                '<style>',
                "@import url('https://fonts.googleapis.com/css2?family=Press+Start+2P&amp;display=swap');",
                '.bit { text-anchor: middle; dominant-baseline: middle; font-family: "Press Start 2P", "Courier New", Courier, monospace; fill: white }',
                '.art { image-rendering: pixelated }',
                '.shape { shape-rendering: crispEdges }',
                '</style>',
                '<image href="', IPFS, 'cup', level.toString(), '.png" height="450" width="290" class="art"/>',
                generateImageText(tokenId, pendingOath, maturity.toString()),
                tags,
                '<svg x="60" y="50" width="190" height="150">'
            )
        );
    }

    function generateImageText(string memory tokenId, string memory pendingOath, string memory maturity) internal pure returns (string memory text) {
        text = string(
            abi.encodePacked(
                '<text x="50%" y="18" class="bit" style="font-size: 12">RELIC #', tokenId,
                '</text><text x="50%" y="330" class="bit" style="font-size: 8">PENDING:', pendingOath,
                ' OATH</text><text x="50%" y="345" class="bit" style="font-size: 8">MATURITY:', maturity
            )
        );
    }

    function generateTextFromToken(
        address underlyingAddress,
        bool isLP,
        uint256 amount
    ) internal view returns (string memory underlying, string memory amountString, string memory tags) {
        amountString = generateDecimalString(amount, IERC20Values(underlyingAddress).decimals());
        if (isLP) {
            IUniswapV2Pair lp = IUniswapV2Pair(underlyingAddress);
            IERC20Values token0 = IERC20Values(lp.token0());
            IERC20Values token1 = IERC20Values(lp.token1());
            string memory token0Symbol = token0.symbol();
            string memory token1Symbol = token1.symbol();
            underlying = string(abi.encodePacked(token0Symbol, '-', token1Symbol));

            (uint256 reserves0, uint256 reserves1, ) = lp.getReserves();
            uint256 amount0 = amount * reserves0 * 1e18 / lp.totalSupply();
            uint256 amount1 = amount * reserves1 * 1e18 / lp.totalSupply();
            tags = string(
                abi.encodePacked(
                    '</text><text x="50%" y="300" class="bit" style="font-size: 8">', token0Symbol, ':', generateDecimalString(amount0, token0.decimals()),
                    '</text><text x="50%" y="315" class="bit" style="font-size: 8">', token1Symbol, ':', generateDecimalString(amount1, token1.decimals())
                )
            );
        } else {
            underlying = IERC20Values(underlyingAddress).symbol();
            tags = string(
                abi.encodePacked(
                    '</text><text x="50%" y="300" class="bit" style="font-size: 8">AMOUNT:', amountString
                )
            );
        }
        tags = string(
            abi.encodePacked(
                tags,
                '</text><text x="50%" y="279" class="bit" style="font-size: 12">', underlying, '</text>'
            )
        );
    }

    function generateBars(address curveAddress, uint256 maturity, uint256 currentMultiplier) internal pure returns (string memory bars) {
        uint256 totalTimeShown = maturity > 365 days ? maturity : 365 days;
        for (uint256 i; i < NUM_BARS; i++) {
            uint256 barHeight = ICurve(curveAddress).curve(totalTimeShown * i / NUM_BARS) * GRAPH_HEIGHT / 100;
            bars = string(abi.encodePacked(
                bars,
                '<rect x="', (BAR_WIDTH * i).toString(),
                '" y="', (GRAPH_HEIGHT - barHeight).toString(),
                '" class="shape',
                '" width="', BAR_WIDTH.toString(),
                '" height="', barHeight.toString(),
                '" style="fill:#fff"/>'
            ));
        }
        bars = string(abi.encodePacked(
            bars,
            '<image href="', IPFS, 'skully.png" x="', ((GRAPH_WIDTH - 15) * maturity / totalTimeShown).toString(),
            '" y="', (GRAPH_HEIGHT - currentMultiplier * GRAPH_HEIGHT / 100 - 6).toString(), '" height="11" width="12" class="art"/>',
            '</svg></svg>'
        ));
    }

    function generateDecimalString(uint256 num, uint256 decimals) internal pure returns (string memory) {
        if (num == 0) {
            return '0';
        }

        uint256 numLength;
        uint256 result;
        do {
            result = num / 10 ** (++numLength);
        } while (result != 0);

        bool lessThanOne = numLength <= decimals;
        uint256 bufferLength;
        if (lessThanOne) {
            bufferLength = decimals + 2;
        } else if (numLength > 19) {
            uint256 difference = numLength - 19;
            decimals -= difference > decimals ? decimals : difference;
            num /= 10 ** difference;
            bufferLength = 20;
        } else {
            bufferLength = numLength + 1;
        }
        bytes memory buffer = new bytes(bufferLength);

        if (lessThanOne) {
            buffer[0] = '0';
            buffer[1] = '.';
            for (uint256 i = 0; i < decimals - numLength; i++) {
                buffer[i + 2] = '0';
            }
        }
        uint256 index = bufferLength - 1;
        while (num != 0) {
            if (!lessThanOne && index == bufferLength - decimals - 1) {
                buffer[index--] = '.';
            }
            buffer[index] = bytes1(uint8(48 + num % 10));
            num /= 10;
            if (index != 0) {
                index--;
            }
        }

        return string(buffer);
    }
}
