// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "openzeppelin-contracts/contracts/utils/Strings.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "base64/base64.sol";
import "../interfaces/INFTDescriptor.sol";
import "../interfaces/IReliquary.sol";

contract NFTDescriptor is INFTDescriptor {
    using Strings for uint256;

    address public immutable reliquary;

    constructor(address _reliquary) {
        reliquary = _reliquary;
    }

    struct LocalVariables_constructTokenURI {
        address underlying;
        string amount;
        string pendingReward;
        uint256 maturity;
        string rewardSymbol;
        string description;
        string attributes;
    }

    /// @notice Generate tokenURI as a base64 encoding from live on-chain values.
    function constructTokenURI(uint256 relicId)
        external
        view
        override
        returns (string memory uri)
    {
        IReliquary _reliquary = IReliquary(reliquary);
        PositionInfo memory position = _reliquary.getPositionForId(relicId);
        PoolInfo memory pool = _reliquary.getPoolInfo(position.poolId);
        LocalVariables_constructTokenURI memory vars;
        vars.underlying = address(_reliquary.getPoolInfo(position.poolId).poolToken);
        vars.amount =
            generateDecimalString(position.amount, IERC20Metadata(vars.underlying).decimals());
        vars.pendingReward = generateDecimalString(_reliquary.pendingReward(relicId), 18);
        vars.maturity = (block.timestamp - position.entry) / 1 days;
        vars.rewardSymbol = IERC20Metadata(address(_reliquary.rewardToken())).symbol();

        vars.description = generateDescription(pool.name);
        vars.attributes = generateAttributes(
            position, vars.amount, vars.pendingReward, vars.rewardSymbol, vars.maturity
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
                        "]}"
                    )
                )
            )
        );
    }

    /// @notice Generate description of the liquidity position for NFT metadata.
    /// @param poolName Name of pool as provided by operator.
    function generateDescription(string memory poolName)
        internal
        pure
        returns (string memory description)
    {
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
        uint256 maturity
    ) internal pure returns (string memory attributes) {
        attributes = string.concat(
            '{"trait_type": "Pool ID", "value": ',
            uint256(position.poolId).toString(),
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
            uint256(position.level + 1).toString(),
            "}"
        );
    }

    /**
     * @notice Generate human-readable string from a number with given decimal places.
     * Does not work for amounts with more than 18 digits before decimal point.
     * @param num A number.
     * @param decimals Number of decimal places.
     */
    function generateDecimalString(uint256 num, uint256 decimals)
        internal
        pure
        returns (string memory decString)
    {
        if (num == 0) {
            return "0";
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
            buffer[0] = "0";
            buffer[1] = ".";
            for (uint256 i = 0; i < decimals - numLength; i++) {
                buffer[i + 2] = "0";
            }
        }
        uint256 index = bufferLength - 1;
        while (num != 0) {
            if (!lessThanOne && index == bufferLength - decimals - 1) {
                buffer[index--] = ".";
            }
            buffer[index] = bytes1(uint8(48 + (num % 10)));
            num /= 10;
            unchecked {
                index--;
            }
        }

        decString = string(buffer);
    }
}
