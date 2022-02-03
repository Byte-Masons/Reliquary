// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import '@openzeppelin/contracts/utils/Strings.sol';
import 'base64-sol/base64.sol';
import './interfaces/ICurve.sol';

library NFTDescriptor {
    using Strings for uint256;

    uint256 private constant NUM_BARS = 20;
    uint256 private constant CANVAS_WIDTH = 290;
    uint256 private constant CANVAS_HEIGHT = 500;
    uint256 private constant BAR_WIDTH = CANVAS_WIDTH / NUM_BARS;

    function constructTokenURI(
        uint256 tokenId,
        string memory underlying,
        uint256 poolId,
        uint256 amount,
        uint256 pendingOath,
        uint256 maturity,
        address curveAddress
    ) public pure returns (string memory) {
        string memory name = string(
            abi.encodePacked(
                'Relic #', tokenId.toString(), ': ', underlying
            )
        );
        string memory description =
            generateDescription(
                underlying,
                poolId,
                amount,
                pendingOath,
                maturity,
                curveAddress
            );
        string memory image = Base64.encode(bytes(generateSVGImage(curveAddress, maturity)));

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
        uint256 poolId,
        uint256 amount,
        uint256 pendingOath,
        uint256 maturity,
        address curveAddress
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
                amount.toString(),
                '\\nPending Oath: ',
                pendingOath.toString(),
                '\\nMaturity: ',
                maturity.toString(),
                '\\nCurrent Reward Multiplier: ',
                ICurve(curveAddress).curve(maturity).toString()
            )
        );
    }

    function generateSVGImage(address curveAddress, uint256 maturity) internal pure returns (string memory svg) {
        svg = string(
            abi.encodePacked(
                '<svg width="290" height="500" viewBox="0 0 290 500" style="background-color:black" xmlns="http://www.w3.org/2000/svg"',
                " xmlns:xlink='http://www.w3.org/1999/xlink'>",
                generateBars(curveAddress, maturity),
                '</svg>'
            )
        );
    }

    function generateBars(address curveAddress, uint256 maturity) internal pure returns (string memory bars) {
        uint256 totalTimeShown = maturity > 365 days ? maturity : 365 days;
        for (uint256 i; i < NUM_BARS; i++) {
            uint256 barHeight = ICurve(curveAddress).curve(totalTimeShown * i / NUM_BARS);
            bars = string(abi.encodePacked(
                bars,
                string(
                    abi.encodePacked(
                        '<rect x="', (BAR_WIDTH * i).toString(),
                        '" y="', (CANVAS_HEIGHT - barHeight).toString(),
                        '" width="', BAR_WIDTH.toString(),
                        '" height="', barHeight.toString(),
                        '" style="fill:rgb(255,255,255)" />'
                    )
                )
            ));
        }
    }
}
