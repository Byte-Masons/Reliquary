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
        address[] childRewarderTokens;
        uint[] childRewarderPeriods;
        uint[] levelMultipliers;
        string name;
        address poolToken;
        uint[] requiredMaturities;
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
    string deployCache;
    address multisig;
    address reliquary;
    address[] rewarderAddresses;
    ParentRewarderRolling[] parentRewarders;
    RollingRewarder[] childRewarders;

    address nftDescriptorNormal;

    function run() external {
        config = vm.readFile("scripts/add_pool/pool_conf.json");
        deployCache = vm.readFile("scripts/add_pool/deploy_cache.json");

        multisig = config.readAddress(".multisig");
        reliquary = config.readAddress(".reliquary");

        Pool[] memory pools = abi.decode(config.parseRaw(".pools"), (Pool[]));
        parentRewarders = abi.decode(deployCache.parseRaw(".parentRewarders"), (ParentRewarderRolling[]));

        vm.startBroadcast();

        for (uint i = 0; i < pools.length; ++i) {
            Pool memory pool = pools[i];

            if (pool.childRewarderTokens.length > 0) {
                ParentRewarderRolling parent = ParentRewarderRolling(parentRewarders[i]);
                for (uint j = 0; j < pool.childRewarderTokens.length; ++j) {
                    address rewardToken = pool.childRewarderTokens[j];
                    uint period = pool.childRewarderPeriods[j];
                    RollingRewarder child = RollingRewarder(parent.createChild(rewardToken, tx.origin));
                    RewardsPool rewardsPool = new RewardsPool(rewardToken, address(child));
                    child.updateDistributionPeriod(period);
                    parent.setChildsRewardPool(address(child), address(rewardsPool));
                    if (multisig != address(0)) {
                        child.transferOwnership(multisig);
                        rewardsPool.transferOwnership(multisig);
                    }
                    rewarderAddresses.push(address(child));
                    console.log("Created child rewarder with reward token: %s, period: %d", rewardToken, period);
                }
            }
        }

        if (multisig != address(0)) {
            _renounceRoles();
        }
        
        vm.stopBroadcast();
    }

    function _renounceRoles() internal {
        bytes32 defaultAdminRole = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);

        for (uint i; i < parentRewarders.length; ++i) {
            parentRewarders[i].grantRole(defaultAdminRole, multisig);
            parentRewarders[i].grantRole(CHILD_SETTER, multisig);
            parentRewarders[i].grantRole(REWARD_SETTER, multisig);
            parentRewarders[i].renounceRole(defaultAdminRole, tx.origin);
            parentRewarders[i].renounceRole(CHILD_SETTER, tx.origin);
            parentRewarders[i].renounceRole(REWARD_SETTER, tx.origin);
        }
    }
}
