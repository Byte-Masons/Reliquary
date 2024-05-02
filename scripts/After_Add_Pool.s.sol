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

        _deployRewarders();

        if (multisig != address(0)) {
            _renounceRoles();
        }
        

        vm.stopBroadcast();
    }

    function _deployRewarders() internal {
        address rewardToken = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        ParentRewarderRolling parent = ParentRewarderRolling(0xc1Df4fC2B3d672A7152C7cF0C63604dfC192B0f9); // TODO: replace with actual parent contract
        address rewarderAddress = parent.createChild(rewardToken, tx.origin);
        RollingRewarder(rewarderAddress).updateDistributionPeriod(14 days);
        rewardsPool = new RewardsPool(rewardToken, rewarderAddress);
        parent.setChildsRewardPool(rewarderAddress, address(rewardsPool));
        rewarderAddresses.push(rewarderAddress);

    }


    function _renounceRoles() internal {
        bytes32 defaultAdminRole = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        rewardsPool.transferOwnership(multisig);
        ParentRewarderRolling parent = ParentRewarderRolling(0xc1Df4fC2B3d672A7152C7cF0C63604dfC192B0f9); // TODO: replace with actual parent contract
        parent.grantRole(defaultAdminRole, multisig);
        parent.grantRole(CHILD_SETTER, multisig);
        parent.grantRole(REWARD_SETTER, multisig);
        parent.renounceRole(defaultAdminRole, tx.origin);
        parent.renounceRole(CHILD_SETTER, tx.origin);
        parent.renounceRole(REWARD_SETTER, tx.origin);
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
