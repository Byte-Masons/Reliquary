// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import '@openzeppelin/contracts/utils/Strings.sol';
import 'base64-sol/base64.sol';
import '../interfaces/INFTDescriptor.sol';
import '../interfaces/IReliquary.sol';

interface IERC20Values {
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

contract NFTDescriptor is INFTDescriptor {
    using Strings for uint;

    /// @notice Constants for drawing graph
    uint private constant GRAPH_WIDTH = 210;
    uint private constant GRAPH_HEIGHT = 30;

    // TODO: testing account, not ipfs to be used in production
    string private constant IPFS = 'https://gateway.pinata.cloud/ipfs/QmaayJ6EGM4JmK8P4eenopFrvExn6cwpeTapxti85ETJP4/';
    uint private constant NUM_CHARACTERS = 3;

    IReliquary public immutable reliquary;

    constructor(IReliquary _reliquary) {
        reliquary = _reliquary;
    }

    /// @notice Generate tokenURI as a base64 encoding from live on-chain values
    function constructTokenURI(uint relicId) external view override returns (string memory) {
        PositionInfo memory position = reliquary.getPositionForId(relicId);
        PoolInfo memory pool = reliquary.getPoolInfo(position.poolId);
        LevelInfo memory levelInfo = reliquary.getLevelInfo(position.poolId);
        address underlying = address(reliquary.lpToken(position.poolId));
        string memory amount = generateDecimalString(position.amount, IERC20Values(underlying).decimals());
        string memory pendingOath = generateDecimalString(reliquary.pendingOath(relicId), 18);
        uint maturity = (block.timestamp - position.entry) / 1 days;

        uint characterId = uint(keccak256(abi.encodePacked(relicId, address(reliquary)))) % NUM_CHARACTERS;

        string memory description = generateDescription(pool.name);
        string memory attributes = generateAttributes(
            position,
            amount,
            pendingOath,
            maturity
        );
        string memory image =
            Base64.encode(
                bytes(
                    string.concat(
                        generateSVGImage(
                            position.level,
                            levelInfo.balance.length,
                            characterId
                        ),
                        generateImageText(
                            relicId,
                            pool.name,
                            pendingOath,
                            maturity
                        ),
                        generateTextFromToken(
                            underlying,
                            position.amount,
                            amount
                        ),
                        '</text>',
                        generateBars(
                            position.level,
                            levelInfo
                        ),
                        '</svg></svg>'
                    )
                )
            );

        return
            string.concat(
                'data:application/json;base64,',
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name":"',
                            string.concat(
                                'Relic #', relicId.toString(), ': ', pool.name
                            ),
                            '", "description":"',
                            description,
                            '", "attributes": [',
                            attributes,
                            '], "image": "',
                            'data:image/svg+xml;base64,',
                            image,
                            '"}'
                        )
                    )
                )
            );
    }

    /// @notice Generate description of the liquidity position for NFT metadata
    /// @param poolName Name of pool as provided by operator
    function generateDescription(
        string memory poolName
    ) internal pure returns (string memory) {
        return
        string.concat(
            'This NFT represents a position in a Reliquary ', poolName, ' pool. ',
            'The owner of this NFT can modify or redeem the position, reducing its maturity accordingly.'
        );
    }

    /// @notice Generate attributes for NFT metadata
    /// @param position Position represented by this Relic
    /// @param pendingOath Amount of OATH that can currently be harvested from this position
    /// @param maturity Weighted average of the maturity deposits into this position
    function generateAttributes(
        PositionInfo memory position,
        string memory amount,
        string memory pendingOath,
        uint maturity
    ) internal pure returns (string memory) {
        return
        string.concat(
            '{"trait_type": "Pool ID", "value": ',
            position.poolId.toString(),
            '}, {"trait_type": "Amount Deposited", "value": "',
            amount,
            '"}, {"trait_type": "Pending Oath", "value": "',
            pendingOath,
            '"}, {"trait_type": "Maturity", "value": "',
            maturity.toString(), ' day', (maturity == 1) ? '' : 's',
            '"}, {"trait_type": "Level", "value": ',
            (position.level + 1).toString(), '}'
        );
    }

    /// @notice Generate the first part of the SVG for this NFT
    /// @param level Current maturity level of the position
    /// @param numLevels Total number of levels in the pool
    function generateSVGImage(
        uint level,
        uint numLevels,
        uint characterId
    ) internal pure returns (string memory svg) {
        level = (level + 1) * 5 / numLevels;
        svg = string.concat(
            '<svg width="290" height="450" viewBox="0 0 290 450" style="background-color:#131313" xmlns="http://www.w3.org/2000/svg">',
            '<style>',
            "@import url('https://fonts.googleapis.com/css2?family=Press+Start+2P&amp;display=swap');",
            '.bit { text-anchor: middle; dominant-baseline: middle; font-family: "Press Start 2P", "Courier New", Courier, monospace; fill: white }',
            '.art { image-rendering: pixelated }',
            '.shape { shape-rendering: crispEdges }',
            '</style>',
            '<image href="', IPFS, characterId.toString(), '/', (level == 0) ? '1' : level.toString(), '.gif', '" height="450" width="290" class="art"/>'
        );
    }

    /// @notice Generate the first part of text labels for this NFT image
    /// @param relicId ID of the NFT/position
    /// @param poolName Name of pool as provided by operator
    /// @param pendingOath Amount of OATH that can currently be harvested from this position
    /// @param maturity Weighted average of the maturity deposits into this position
    function generateImageText(
        uint relicId,
        string memory poolName,
        string memory pendingOath,
        uint maturity
    ) internal pure returns (string memory text) {
        text = string.concat(
            '<text x="50%" y="20" class="bit" style="font-size: 12">RELIC #', relicId.toString(),
            '</text><text x="50%" y="280" class="bit" style="font-size: 12">', poolName,
            '</text><text x="50%" y="360" class="bit" style="font-size: 8">PENDING:', pendingOath,
            ' OATH</text><text x="50%" y="380" class="bit" style="font-size: 8">MATURITY:', maturity.toString(),
            ' DAY', (maturity == 1) ? '' : 'S', '</text>'
        );
    }

    /// @notice Generate further text labels specific to the underlying token
    /// @param underlying Address of underlying token for this position
    /// @param amount Amount of underlying tokens deposited in this position
    function generateTextFromToken(
        address underlying,
        uint amount,
        string memory amountString
    ) internal view virtual returns (string memory tags) {
        tags = string.concat(
            '<text x="50%" y="320" class="bit" style="font-size: 8">AMOUNT:', amountString
        );
    }

    /// @notice Generate bar graph of this pool's bonding curve and indicator of the position's placement
    /// @param level Current level of the position
    /// @param levelInfo Level info for this pool
    function generateBars(uint level, LevelInfo memory levelInfo) internal pure returns (string memory bars) {
        uint highestAllocPoint = levelInfo.allocPoint[0];
        for (uint i = 1; i < levelInfo.allocPoint.length; i++) {
            if (levelInfo.allocPoint[i] > highestAllocPoint) {
                highestAllocPoint = levelInfo.allocPoint[i];
            }
        }

        uint barWidth = GRAPH_WIDTH * 10 / levelInfo.allocPoint.length;
        uint barWidthInt = barWidth / 10;
        string memory barWidthString = string.concat((barWidthInt > 5 ? barWidthInt - 5 : barWidthInt).toString(), '.', (barWidth % 10).toString());
        bars = '<svg x="43" y="226" width="210" height="30">';
        for (uint i; i < levelInfo.allocPoint.length; i++) {
            uint barHeight = levelInfo.allocPoint[i] * GRAPH_HEIGHT / highestAllocPoint;
            bars = string.concat(
                bars,
                '<rect x="', (barWidth * i / 10).toString(), '.', (barWidth * i % 10).toString(),
                '" y="', (GRAPH_HEIGHT - barHeight).toString(),
                '" class="shape',
                '" width="', barWidthString,
                '" height="', barHeight.toString(),
                '" style="fill:#', (i == level) ? 'e6de59' : 'fff', '"/>'
            );
        }
    }

    /// @notice Generate human-readable string from a number with given decimal places.
    /// Does not work for amounts with more than 18 digits before decimal point.
    /// @param num A number
    /// @param decimals Number of decimal places
    function generateDecimalString(uint num, uint decimals) internal pure returns (string memory) {
        if (num == 0) {
            return '0';
        }

        uint numLength;
        uint result;
        do {
            result = num / 10 ** (++numLength);
        } while (result != 0);

        bool lessThanOne = numLength <= decimals;
        uint bufferLength;
        if (lessThanOne) {
            bufferLength = decimals + 2;
        } else if (numLength > 19) {
            uint difference = numLength - 19;
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
            for (uint i = 0; i < decimals - numLength; i++) {
                buffer[i + 2] = '0';
            }
        }
        uint index = bufferLength - 1;
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
