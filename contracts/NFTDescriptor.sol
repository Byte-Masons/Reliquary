// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import '@openzeppelin/contracts/utils/Strings.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import 'base64-sol/base64.sol';
import './interfaces/INFTDescriptor.sol';

interface IERC20Values {
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

contract NFTDescriptor {
    using Strings for uint256;

    /// @notice Constants for drawing graph
    uint256 private constant GRAPH_WIDTH = 180;
    uint256 private constant GRAPH_HEIGHT = 150;

    // TODO: testing account, not ipfs to be used in production
    string private constant IPFS = 'https://gateway.pinata.cloud/ipfs/QmbYvNccKU3e2LFGnTDHa2asxQat2Ldw1G2wZ4iNzr59no/';

    /// @notice Generate tokenURI as a base64 encoding from live on-chain values
    /// @param params Struct containing all parameters for this function (avoids stack too deep error)
    function constructTokenURI(INFTDescriptor.ConstructTokenURIParams memory params) public view returns (string memory) {
        string memory tokenId = params.tokenId.toString();
        string memory poolId = params.poolId.toString();
        string memory amount = generateDecimalString(params.amount, IERC20Values(params.underlying).decimals());
        string memory pendingOath = generateDecimalString(params.pendingOath, 18);

        string memory name = string(
            abi.encodePacked(
                'Relic #', tokenId, ': ', params.poolName
            )
        );
        string memory description =
            generateDescription(
                params.poolName,
                poolId,
                amount,
                pendingOath,
                params.maturity
            );
        string memory image =
            Base64.encode(
                bytes(
                    string(
                        abi.encodePacked(
                            generateSVGImage(
                                tokenId,
                                params.poolName,
                                pendingOath,
                                params.maturity,
                                params.level
                            ),
                            generateTextFromToken(
                                params.underlying,
                                params.isPair,
                                params.amount,
                                amount
                            ),
                            '</text>',
                            generateBars(
                                params.level,
                                params.levels
                            ),
                            '</svg></svg>'
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

    /// @notice Generate description of the liquidity position as NFT attribute
    /// @param poolName Name of pool as provided by operator
    /// @param poolId ID of pool
    /// @param amount Amount of underlying tokens deposited in this position
    /// @param pendingOath Amount of OATH that can currently be harvested from this position
    /// @param maturity Weighted average of the maturity deposits into this position
    function generateDescription(
        string memory poolName,
        string memory poolId,
        string memory amount,
        string memory pendingOath,
        uint256 maturity
    ) internal pure returns (string memory) {
        return
        string(
            abi.encodePacked(
                'This NFT represents a liquidity position in a Reliquary ',
                poolName,
                ' pool. ',
                'The owner of this NFT can modify or redeem the position.\\n',
                '\\nPool ID: ',
                poolId,
                '\\nAmount Deposited: ',
                amount,
                '\\nPending Oath: ',
                pendingOath,
                '\\nMaturity: ',
                maturity.toString()
            )
        );
    }

    /// @notice Generate the first part of the SVG for this NFT
    /// @param tokenId ID of the NFT/position
    /// @param poolName Name of pool as provided by operator
    /// @param pendingOath Amount of OATH that can currently be harvested from this position
    /// @param maturity Weighted average of the maturity deposits into this position
    /// @param level Current maturity level of the position
    function generateSVGImage(
        string memory tokenId,
        string memory poolName,
        string memory pendingOath,
        uint256 maturity,
        uint256 level
    ) internal pure returns (string memory svg) {
        level = level > 4 ? 5 : level + 1;
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
                generateImageText(tokenId, poolName, pendingOath, maturity.toString())
            )
        );
    }

    /// @notice Generate the first part of text labels for this NFT image
    /// @param tokenId ID of the NFT/position
    /// @param poolName Name of pool as provided by operator
    /// @param pendingOath Amount of OATH that can currently be harvested from this position
    /// @param maturity Weighted average of the maturity deposits into this position
    function generateImageText(
        string memory tokenId,
        string memory poolName,
        string memory pendingOath,
        string memory maturity
    ) internal pure returns (string memory text) {
        text = string(
            abi.encodePacked(
                '<text x="50%" y="18" class="bit" style="font-size: 12">RELIC #', tokenId,
                '</text><text x="50%" y="279" class="bit" style="font-size: 12">', poolName,
                '</text><text x="50%" y="330" class="bit" style="font-size: 8">PENDING:', pendingOath,
                ' OATH</text><text x="50%" y="345" class="bit" style="font-size: 8">MATURITY:', maturity, '</text>'
            )
        );
    }

    /// @notice Generate further text labels specific to the underlying token
    /// @param underlying Address of underlying token for this position
    /// @param isPair Whether the underlying token is an IUniswapV2Pair LP
    /// @param amount Amount of underlying tokens deposited in this position
    /// @param amountString amount as string
    function generateTextFromToken(
        address underlying,
        bool isPair,
        uint256 amount,
        string memory amountString
    ) internal view returns (string memory tags) {
        if (isPair) {
            IUniswapV2Pair lp = IUniswapV2Pair(underlying);
            IERC20Values token0 = IERC20Values(lp.token0());
            IERC20Values token1 = IERC20Values(lp.token1());

            (uint256 reserves0, uint256 reserves1, ) = lp.getReserves();
            uint256 amount0 = amount * reserves0 / lp.totalSupply();
            uint256 amount1 = amount * reserves1 / lp.totalSupply();
            tags = string(
                abi.encodePacked(
                    '<text x="50%" y="300" class="bit" style="font-size: 8">', token0.symbol(), ':', generateDecimalString(amount0, token0.decimals()),
                    '</text><text x="50%" y="315" class="bit" style="font-size: 8">', token1.symbol(), ':', generateDecimalString(amount1, token1.decimals())
                )
            );
        } else {
            tags = string(
                abi.encodePacked(
                    '<text x="50%" y="300" class="bit" style="font-size: 8">AMOUNT:', amountString
                )
            );
        }
    }

    /// @notice Generate bar graph of this pool's bonding curve and indicator of the position's placement
    /// @param level Current level of the position
    /// @param levels The levels for this pool, including their required maturity and alloc points
    function generateBars(uint256 level, INFTDescriptor.Level[] memory levels) internal pure returns (string memory bars) {
        uint256 numBars = levels.length;
        uint256 barWidth = GRAPH_WIDTH * 10 / numBars;
        string memory barWidthString = string(abi.encodePacked((barWidth / 10).toString(), '.', (barWidth % 10).toString()));
        bars = '<svg x="58" y="50" width="180" height="150">';
        for (uint256 i; i < numBars; i++) {
            uint256 barHeight = levels[i].allocPoint * GRAPH_HEIGHT / levels[numBars - 1].allocPoint;
            bars = string(abi.encodePacked(
                bars,
                '<rect x="', (barWidth * i / 10).toString(), '.', (barWidth * i % 10).toString(),
                '" y="', (GRAPH_HEIGHT - barHeight).toString(),
                '" class="shape',
                '" width="', barWidthString,
                '" height="', barHeight.toString(),
                '" style="fill:#', (i == level) ? 'e6de59' : 'fff', '"/>'
            ));
        }
    }

    /// @notice Generate human-readable string from a number with given decimal places.
    /// Does not work for amounts with more than 18 digits before decimal point.
    /// @param num A number
    /// @param decimals Number of decimal places
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
            unchecked {
                index--;
            }
        }

        return string(buffer);
    }
}
