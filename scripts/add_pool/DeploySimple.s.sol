// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Reliquary, IReliquary} from "contracts/Reliquary.sol";
import {OwnableCurve} from "contracts/emission_curves/OwnableCurve.sol";
import {DepositHelperERC4626} from "contracts/helpers/DepositHelperERC4626.sol";
import {DepositHelperReaperVault} from "contracts/helpers/DepositHelperReaperVault.sol";
import {NFTDescriptor, NFTDescriptorPair} from "contracts/nft_descriptors/NFTDescriptorPair.sol";
import {NFTDescriptorSingle4626} from "contracts/nft_descriptors/NFTDescriptorSingle4626.sol";
import {ParentRewarderRolling, RollingRewarder} from "contracts/rewarders/ParentRewarder-Rolling.sol";
import {RewardsPool} from "contracts/rewarders/RewardsPool.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

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

    bytes32 constant OPERATOR = keccak256("OPERATOR");
    bytes32 constant CHILD_SETTER = keccak256("CHILD_SETTER");
    bytes32 constant REWARD_SETTER = keccak256("REWARD_SETTER");

    string config;
    address multisig;
    IReliquary reliquary;
    RewardsPool rewardsPool;
    address[] rewarderAddresses;

    address nftDescriptorNormal;
    address nftDescriptor4626;
    address nftDescriptorPair;
    address depositHelper4626;
    address depositHelperReaperVault;

    function run() external {
        config = vm.readFile("scripts/add_pool/pool_conf.json");

        Pool[] memory pools = abi.decode(config.parseRaw(".pools"), (Pool[]));
        reliquary = IReliquary(config.readAddress(".reliquary"));

        vm.startBroadcast();
        
        for (uint i = 0; i < pools.length; ++i) {
            Pool memory pool = pools[i];
            address nftDescriptor = _deployHelpers(pool.tokenType);

            address rewarder;
            if (pool.childRewarderTokens.length > 0) {
                rewarder = address(new ParentRewarderRolling(address(reliquary), i));
            }

            rewarderAddresses.push(rewarder);

            console.log("");
            console.log("#######################################################");
            console.log("Add pool: %s", pool.name);
            console.log("Params:");
            console.log("  allocPoint: %d", pool.allocPoint);
            console.log("  _poolToken: %s", pool.poolToken);
            console.log("  _rewarder: %s", rewarder);
            console_logArray("  requiredMaturities", pool.requiredMaturities);
            console_logArray("  levelMultipliers", pool.levelMultipliers);
            console.log("  name: %s", pool.name);
            console.log("  _nftDescriptor: %s", nftDescriptor);
            console.log("  allowPartialWithdrawals: %s", pool.allowPartialWithdrawals);
            console.log("#######################################################");
        }

        console.log("Add pools above, then run the next script: After_Add_Pool.s.sol");

        string memory rewardersJson = vm.serializeAddress("", "parentRewarders", rewarderAddresses);
        vm.writeFile("scripts/add_pool/deploy_cache.json", rewardersJson);
    
        vm.stopBroadcast();
    }

    function _deployHelpers(string memory poolTokenType) internal returns (address nftDescriptor) {
        bytes32 typeHash = keccak256(bytes(poolTokenType));
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
            if (depositHelper4626 == address(0)) {
                depositHelper4626 = address(new DepositHelperERC4626(reliquary, config.readAddress(".weth")));
            }
        } else if (typeHash == keccak256("pair")) {
            if (nftDescriptorPair == address(0)) {
                nftDescriptorPair = address(new NFTDescriptorPair(address(reliquary)));
            }
            nftDescriptor = nftDescriptorPair;
        } else if (typeHash == keccak256("reaper-vault")) {
            if (nftDescriptorNormal == address(0)) {
                nftDescriptorNormal = address(new NFTDescriptor(address(reliquary)));
            }
            nftDescriptor = nftDescriptorPair;
            if (depositHelperReaperVault == address(0)) {
                depositHelperReaperVault = address(new DepositHelperReaperVault(reliquary, config.readAddress(".weth")));
            }
        } else {
            revert(string.concat("invalid token type ", poolTokenType));
        }
    }


    function console_logArray(string memory label, uint[] memory arr) internal {
        string memory str = "[";
        for (uint i = 0; i < arr.length; i++) {
            str = string.concat(str, Strings.toString(arr[i]));
            if (i < arr.length - 1) {
                str = string.concat(str, ", ");
            }
        }
        str = string.concat(str, "]"); 
        console.log("%s: %s", label, str);
    }
}