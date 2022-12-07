// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "contracts/Reliquary.sol";
import "contracts/emission_curves/OwnableCurve.sol";
import "contracts/nft_descriptors/NFTDescriptor.sol";
import "contracts/nft_descriptors/NFTDescriptorPair.sol";
import "contracts/nft_descriptors/NFTDescriptorSingle4626.sol";
import "contracts/helpers/DepositHelper.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

contract Deploy is Script {
    using stdJson for string;
    using Strings for uint;

    struct Pool {
        uint allocPoint;
        uint[] levelMultipliers;
        string name;
        address poolToken;
        uint[] requiredMaturities;
        string tokenType;
    }

    uint[] requiredMaturities;
    uint[] levelMultipliers;

    bytes32 constant OPERATOR = keccak256("OPERATOR");
    bytes32 constant EMISSION_CURVE = keccak256("EMISSION_CURVE");

    function run() external {
        string memory config = vm.readFile("scripts/deploy_conf.json");
        address multisig = config.readAddress(".multisig");
        address rewardToken = config.readAddress(".rewardToken");
        uint emissionRate = config.readUint(".emissionRate");

        vm.startBroadcast();

        OwnableCurve curve = new OwnableCurve(emissionRate);

        Reliquary reliquary = new Reliquary(rewardToken, address(curve));

        reliquary.grantRole(OPERATOR, tx.origin);

        address nftDescriptorNormal;
        address nftDescriptor4626;
        address nftDescriptorPair;
        Pool[] memory pools = abi.decode(config.parseRaw(".pools"), (Pool[]));
        for (uint i = 0; i < pools.length; ++i) {
            Pool memory pool = pools[i];

            address nftDescriptor;
            bytes32 typeHash = keccak256(bytes(pool.tokenType));
            if (typeHash == keccak256("normal")) {
                if (nftDescriptorNormal == address(0)) {
                    nftDescriptorNormal = address(new NFTDescriptor(address(reliquary)));
                }
                nftDescriptor = nftDescriptorNormal;
            } else if (typeHash == keccak256("4626")) {
                if (nftDescriptor4626 == address(0)) {
                    nftDescriptor4626 = address(new NFTDescriptorSingle4626(address(reliquary)));
                }
                nftDescriptor = nftDescriptor4626;
            } else if (typeHash == keccak256("pair")) {
                if (nftDescriptorPair == address(0)) {
                    nftDescriptorPair = address(new NFTDescriptorPair(address(reliquary)));
                }
                nftDescriptor = nftDescriptorPair;
            } else {
                revert(string.concat("invalid token type ", pool.tokenType));
            }

            reliquary.addPool(
                pool.allocPoint,
                pool.poolToken,
                address(0),
                pool.requiredMaturities,
                pool.levelMultipliers,
                pool.name,
                nftDescriptor
            );
        }

        if (multisig != address(0)) {
            bytes32 defaultAdminRole = reliquary.DEFAULT_ADMIN_ROLE();
            reliquary.grantRole(defaultAdminRole, multisig);
            reliquary.grantRole(OPERATOR, multisig);
            reliquary.grantRole(EMISSION_CURVE, multisig);
            reliquary.renounceRole(OPERATOR, tx.origin);
            reliquary.renounceRole(defaultAdminRole, tx.origin);
            curve.transferOwnership(multisig);
        }

        new DepositHelper(address(reliquary));

        vm.stopBroadcast();
    }
}
