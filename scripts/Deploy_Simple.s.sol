// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Reliquary} from "contracts/Reliquary.sol";
import {OwnableCurve} from "contracts/emission_curves/OwnableCurve.sol";
import {DepositHelperERC4626} from "contracts/helpers/DepositHelperERC4626.sol";
import {NFTDescriptor, NFTDescriptorPair} from "contracts/nft_descriptors/NFTDescriptorPair.sol";
import {NFTDescriptorSingle4626} from "contracts/nft_descriptors/NFTDescriptorSingle4626.sol";
import {ParentRewarderRolling, RollingRewarder} from "contracts/rewarders/ParentRewarder-Rolling.sol";
import {RewardsPool} from "contracts/rewarders/RewardsPool.sol";

contract Deploy is Script {
    using stdJson for string;

    struct Pool {
        uint allocPoint;
        bool allowPartialWithdrawals;
        uint[] levelMultipliers;
        string name;
        address poolToken;
        uint[] requiredMaturities;
        int rewarderIndex;
        string tokenType;
    }

    struct ParentRewarder {
        uint poolId;
    }

    struct Rewarder {
        uint parentIndex;
        address rewardToken;
    }

    bytes32 constant OPERATOR = keccak256("OPERATOR");
    bytes32 constant CHILD_SETTER = keccak256("CHILD_SETTER");
    bytes32 constant REWARD_SETTER = keccak256("REWARD_SETTER");

    string config;
    address multisig;
    address reliquary;
    RewardsPool rewardsPool;
    address[] rewarderAddresses;
    ParentRewarderRolling[] parentRewarders;
    address nftDescriptorNormal;

    function run() external {
        config = vm.readFile("scripts/deploy_conf.json");
        multisig = config.readAddress(".multisig");

        Pool[] memory pools = abi.decode(config.parseRaw(".pools"), (Pool[]));
        reliquary = 0xF512283347C174399Cc3E11492ead8b49BD2712e;
        vm.startBroadcast();
        for (uint i = 0; i < pools.length; ++i) {
            Pool memory pool = pools[i];
            address nftDescriptor = _deployHelpers(pool.tokenType);
        }

        _deployRewarders();
    
        vm.stopBroadcast();
    }

    function _deployRewarders() internal {
        ParentRewarder[] memory parents = abi.decode(config.parseRaw(".parentRewarders"), (ParentRewarder[]));
        for (uint i; i < parents.length; ++i) {
            ParentRewarder memory parent = parents[i];

            ParentRewarderRolling newParent = new ParentRewarderRolling(
                reliquary, parent.poolId
            );

            newParent.grantRole(CHILD_SETTER, tx.origin);
            newParent.grantRole(REWARD_SETTER, tx.origin);
            parentRewarders.push(newParent);
            rewarderAddresses.push(address(newParent));
        }
    }

    function _deployHelpers(string memory poolTokenType) internal returns (address nftDescriptor) {
        bytes32 typeHash = keccak256(bytes(poolTokenType));
        if (typeHash == keccak256("normal")) {
            if (nftDescriptorNormal == address(0)) {
                nftDescriptorNormal = address(new NFTDescriptor(address(reliquary)));
            }
            nftDescriptor = nftDescriptorNormal;
        } else {
            revert(string.concat("invalid token type ", poolTokenType));
        }
    }
}

            // reliquary.addPool(
            //     66,
            //     0x42c95788F791a2be3584446854c8d9BB01BE88A9,
            //     address(rewarder),
            //     [0],
            //     [100],
            //     "HBR Staking",
            //     nftDescriptor,
            //     true
            // );
