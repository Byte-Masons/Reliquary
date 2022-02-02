// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import '@openzeppelin/contracts/utils/Strings.sol';
import 'base64-sol/base64.sol';
import './interfaces/ICurve.sol';

library NFTDescriptor {
    using Strings for uint256;

    uint256 private constant NUM_LINES = 20;
    uint256 private constant CANVAS_WIDTH = 290;
    uint256 private constant CANVAS_HEIGHT = 500;

    function constructTokenURI(
        uint256 tokenId,
        string memory underlying,
        uint256 poolId,
        uint256 amount,
        uint256 pendingOath,
        uint256 entry,
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
                entry,
                curveAddress
            );
        string memory image = Base64.encode(bytes(generateSVGImage(curveAddress, entry)));

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
        uint256 entry,
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
                '\\nEntry Time: ',
                entry.toString(),
                '\\nCurrent Reward Multiplier: ',
                ICurve(curveAddress).curve(entry).toString()
            )
        );
    }

    function generateSVGImage(address curveAddress, uint256 entry) internal pure returns (string memory svg) {
        svg = string(
            abi.encodePacked(
                '<svg width="291" height="499" style="background-color:black" viewBox="0 0 290 500" xmlns="http://www.w3.org/2000/svg"',
                " xmlns:xlink='http://www.w3.org/1999/xlink'>",
                generatePath(curveAddress, entry),
                '</svg>'
            )
        );
    }

    function generatePath(address curveAddress, uint256 entry) internal pure returns (string memory path) {
        uint256 startY = CANVAS_HEIGHT - ICurve(curveAddress).curve(0);
        path = string(abi.encodePacked(
            '<path d="M0,', startY.toString()
        ));

        uint256 totalTimeShown = entry > 365 days ? entry : 365 days;
        for (uint256 i = 1; i <= NUM_LINES; i++) {
            uint256 x = CANVAS_WIDTH * i / NUM_LINES;
            uint256 y = CANVAS_HEIGHT - ICurve(curveAddress).curve(totalTimeShown * i / NUM_LINES);
            path = string(abi.encodePacked(
                path,
                ' L', x.toString(), ',', y.toString()
            ));
        }

        path = string(abi.encodePacked(
            path,
            ' L', CANVAS_WIDTH.toString(), ',', startY.toString(), ' Z" fill="white" stroke-width="0" />'
        ));
    }
}
