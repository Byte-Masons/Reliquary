// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "openzeppelin-contracts/contracts/utils/Strings.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "base64/base64.sol";
import "../interfaces/INFTDescriptor.sol";
import "../interfaces/IReliquary.sol";

contract NFTDescriptor is INFTDescriptor {
    using Strings for uint;

    /// @notice Constants for drawing graph.
    uint private constant GRAPH_WIDTH = 180;
    uint private constant GRAPH_HEIGHT = 150;

    // TODO: testing account, not ipfs to be used in production
    string private constant IPFS = "https://gateway.pinata.cloud/ipfs/QmbYvNccKU3e2LFGnTDHa2asxQat2Ldw1G2wZ4iNzr59no/";

    address public immutable reliquary;

    constructor(address _reliquary) {
        reliquary = _reliquary;
    }

    struct LocalVariables_constructTokenURI {
        address underlying;
        string amount;
        string pendingReward;
        uint maturity;
        string rewardSymbol;
        string description;
        string attributes;
        string image;
    }

    /// @notice Generate tokenURI as a base64 encoding from live on-chain values.
    function constructTokenURI(uint relicId) external view override returns (string memory uri) {
        IReliquary _reliquary = IReliquary(reliquary);
        PositionInfo memory position = _reliquary.getPositionForId(relicId);
        PoolInfo memory pool = _reliquary.getPoolInfo(position.poolId);
        LevelInfo memory levelInfo = _reliquary.getLevelInfo(position.poolId);
        LocalVariables_constructTokenURI memory vars;
        vars.underlying = address(_reliquary.poolToken(position.poolId));
        vars.amount = generateDecimalString(position.amount, IERC20Metadata(vars.underlying).decimals());
        vars.pendingReward = generateDecimalString(_reliquary.pendingReward(relicId), 18);
        vars.maturity = (block.timestamp - position.entry) / 1 days;
        vars.rewardSymbol = IERC20Metadata(address(_reliquary.rewardToken())).symbol();

        vars.description = generateDescription(pool.name);
        vars.attributes =
            generateAttributes(position, vars.amount, vars.pendingReward, vars.rewardSymbol, vars.maturity);
        vars.image = Base64.encode(
            bytes(
                string.concat(
                    generateSVGImage(position.level, levelInfo.balance.length),
                    generateImageText(relicId, pool.name, vars.pendingReward, vars.rewardSymbol, vars.maturity),
                    generateTextFromToken(vars.underlying, position.amount, vars.amount),
                    "</text>",
                    generateBars(position.level, levelInfo),
                    "</svg></svg>"
                )
            )
        );

        uri = string.concat(
            "data:application/json;base64,",
            Base64.encode(
                bytes(
                    abi.encodePacked(
                        '{"name":"',
                        string.concat("Relic #", relicId.toString(), ": ", pool.name),
                        '", "description":"',
                        vars.description,
                        '", "attributes": [',
                        vars.attributes,
                        '], "image": "',
                        "data:image/svg+xml;base64,",
                        vars.image,
                        '"}'
                    )
                )
            )
        );
    }

    /// @notice Generate description of the liquidity position for NFT metadata.
    /// @param poolName Name of pool as provided by operator.
    function generateDescription(string memory poolName) internal pure returns (string memory description) {
        description = string.concat(
            "This NFT represents a position in a Reliquary ",
            poolName,
            " pool. ",
            "The owner of this NFT can modify or redeem the position."
        );
    }

    /**
     * @notice Generate attributes for NFT metadata.
     * @param position Position represented by this Relic.
     * @param pendingReward Amount of reward token that can currently be harvested from this position.
     * @param maturity Weighted average of the maturity deposits into this position.
     */
    function generateAttributes(
        PositionInfo memory position,
        string memory amount,
        string memory pendingReward,
        string memory rewardSymbol,
        uint maturity
    ) internal pure returns (string memory attributes) {
        attributes = string.concat(
            '{"trait_type": "Pool ID", "value": ',
            position.poolId.toString(),
            '}, {"trait_type": "Amount Deposited", "value": "',
            amount,
            '"}, {"trait_type": "Pending ',
            rewardSymbol,
            '", "value": "',
            pendingReward,
            '"}, {"trait_type": "Maturity", "value": "',
            maturity.toString(),
            " day",
            (maturity == 1) ? "" : "s",
            '"}, {"trait_type": "Level", "value": ',
            (position.level + 1).toString(),
            "}"
        );
    }

    /**
     * @notice Generate the first part of the SVG for this NFT.
     * @param level Current maturity level of the position.
     * @param numLevels Total number of levels in the pool.
     */
    function generateSVGImage(uint level, uint numLevels) internal pure returns (string memory svg) {
        level = (level + 1) * 5 / numLevels;
        svg = string.concat(
            '<svg width="290" height="450" viewBox="0 0 290 450" style="background-color:#131313" xmlns="http://www.w3.org/2000/svg">',
            "<style>",
            "@import url('https://fonts.googleapis.com/css2?family=Press+Start+2P&amp;display=swap');",
            '.bit { text-anchor: middle; dominant-baseline: middle; font-family: "Press Start 2P", "Courier New", Courier, monospace; fill: white }',
            ".art { image-rendering: pixelated }",
            ".shape { shape-rendering: crispEdges }",
            "</style>",
            '<image href="',
            IPFS,
            "cup",
            (level == 0) ? "1" : level.toString(),
            ".png",
            '" height="450" width="290" class="art"/>'
        );
    }

    /**
     * @notice Generate the first part of text labels for this NFT image.
     * @param relicId ID of the NFT/position.
     * @param poolName Name of pool as provided by operator.
     * @param pendingReward Amount of reward token that can currently be harvested from this position.
     * @param maturity Weighted average of the maturity deposits into this position.
     */
    function generateImageText(
        uint relicId,
        string memory poolName,
        string memory pendingReward,
        string memory rewardSymbol,
        uint maturity
    ) internal pure returns (string memory text) {
        text = string.concat(
            '<text x="50%" y="20" class="bit" style="font-size: 12">RELIC #',
            relicId.toString(),
            '</text><text x="50%" y="280" class="bit" style="font-size: 12">',
            poolName,
            '</text><text x="50%" y="330" class="bit" style="font-size: 8">PENDING:',
            pendingReward,
            " ",
            rewardSymbol,
            '</text><text x="50%" y="345" class="bit" style="font-size: 8">MATURITY:',
            maturity.toString(),
            " DAY",
            (maturity == 1) ? "" : "S",
            "</text>"
        );
    }

    /// @notice Generate further text labels specific to the underlying token.
    /// @param amountString Amount of underlying tokens deposited in this position.
    function generateTextFromToken(
        address, //underlying
        uint, //amount
        string memory amountString
    ) internal view virtual returns (string memory text) {
        text = string.concat('<text x="50%" y="300" class="bit" style="font-size: 8">AMOUNT:', amountString);
    }

    /**
     * @notice Generate bar graph of this pool's bonding curve and indicator of the position's placement.
     * @param level Current level of the position.
     * @param levelInfo Level info for this pool.
     */
    function generateBars(uint level, LevelInfo memory levelInfo) internal pure returns (string memory bars) {
        uint highestMultiplier = levelInfo.multipliers[0];
        for (uint i = 1; i < levelInfo.multipliers.length; i++) {
            if (levelInfo.multipliers[i] > highestMultiplier) {
                highestMultiplier = levelInfo.multipliers[i];
            }
        }

        uint barWidth = GRAPH_WIDTH * 10 / levelInfo.multipliers.length;
        uint barWidthInt = barWidth / 10;
        string memory barWidthString =
            string.concat((barWidthInt > 5 ? barWidthInt - 5 : barWidthInt).toString(), ".", (barWidth % 10).toString());
        bars = '<svg x="58" y="50" width="180" height="150">';
        for (uint i; i < levelInfo.multipliers.length; i++) {
            uint barHeight = levelInfo.multipliers[i] * GRAPH_HEIGHT / highestMultiplier;
            bars = string.concat(
                bars,
                '<rect x="',
                (barWidth * i / 10).toString(),
                ".",
                (barWidth * i % 10).toString(),
                '" y="',
                (GRAPH_HEIGHT - barHeight).toString(),
                '" class="shape',
                '" width="',
                barWidthString,
                '" height="',
                barHeight.toString(),
                '" style="fill:#',
                (i == level) ? "e6de59" : "fff",
                '"/>'
            );
        }
    }

    /**
     * @notice Generate human-readable string from a number with given decimal places.
     * Does not work for amounts with more than 18 digits before decimal point.
     * @param num A number.
     * @param decimals Number of decimal places.
     */
    function generateDecimalString(uint num, uint decimals) internal pure returns (string memory decString) {
        if (num == 0) {
            return "0";
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
            buffer[0] = "0";
            buffer[1] = ".";
            for (uint i = 0; i < decimals - numLength; i++) {
                buffer[i + 2] = "0";
            }
        }
        uint index = bufferLength - 1;
        while (num != 0) {
            if (!lessThanOne && index == bufferLength - decimals - 1) {
                buffer[index--] = ".";
            }
            buffer[index] = bytes1(uint8(48 + num % 10));
            num /= 10;
            unchecked {
                index--;
            }
        }

        decString = string(buffer);
    }
}
