// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Reliquary} from "contracts/Reliquary.sol";
import {OwnableCurve} from "contracts/emission_curves/OwnableCurve.sol";
import {DepositHelperERC4626} from "contracts/helpers/DepositHelperERC4626.sol";
import {NFTDescriptor, NFTDescriptorPair} from "contracts/nft_descriptors/NFTDescriptorPair.sol";
import {NFTDescriptorSingle4626} from "contracts/nft_descriptors/NFTDescriptorSingle4626.sol";
import {ParentRewarderRolling} from "contracts/rewarders/ParentRewarder-Rolling.sol";

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
    bytes32 constant EMISSION_CURVE = keccak256("EMISSION_CURVE");
    bytes32 constant CHILD_SETTER = keccak256("CHILD_SETTER");
    bytes32 constant REWARD_SETTER = keccak256("REWARD_SETTER");

    string config;
    address multisig;
    Reliquary reliquary;
    OwnableCurve emissionCurve;
    address[] rewarderAddresses;
    ParentRewarderRolling[] parentRewarders;
    address nftDescriptorNormal;
    address nftDescriptor4626;
    address nftDescriptorPair;
    address depositHelper4626;

    function run() external {
        config = vm.readFile("scripts/deploy_conf.json");
        string memory name = config.readString(".name");
        string memory symbol = config.readString(".symbol");
        multisig = config.readAddress(".multisig");
        address rewardToken = config.readAddress(".rewardToken");
        address thenaToken = config.readAddress(".thenaToken");
        address voter = config.readAddress(".voter");
        address thenaReceiver = config.readAddress(".thenaReceiver");
        uint emissionRate = config.readUint(".emissionRate");
        Pool[] memory pools = abi.decode(config.parseRaw(".pools"), (Pool[]));

        vm.startBroadcast();

        emissionCurve = new OwnableCurve(emissionRate);

        reliquary = new Reliquary(rewardToken, address(emissionCurve), thenaToken, voter, thenaReceiver, name, symbol);


        reliquary.grantRole(OPERATOR, tx.origin);
        for (uint i = 0; i < pools.length; ++i) {
            Pool memory pool = pools[i];

            address nftDescriptor = _deployHelpers(pool.tokenType);

            reliquary.addPool(
                pool.allocPoint,
                pool.poolToken,
                address(0),
                pool.requiredMaturities,
                pool.levelMultipliers,
                pool.name,
                nftDescriptor,
                pool.allowPartialWithdrawals
            );
        }

        _deployRewarders();

        if (multisig != address(0)) {
            _renounceRoles();
        }

        vm.stopBroadcast();
    }

    function _deployRewarders() internal {
        ParentRewarder[] memory parents = abi.decode(config.parseRaw(".parentRewarders"), (ParentRewarder[]));
        for (uint i; i < parents.length; ++i) {
            ParentRewarder memory parent = parents[i];

            ParentRewarderRolling newParent = new ParentRewarderRolling(
                address(reliquary), parent.poolId
            );

            newParent.grantRole(CHILD_SETTER, tx.origin);
            newParent.grantRole(REWARD_SETTER, tx.origin);
            parentRewarders.push(newParent);
            rewarderAddresses.push(address(newParent));

            Pool[] memory pools = abi.decode(config.parseRaw(".pools"), (Pool[]));
            
            reliquary.modifyPool(0, 100, address(newParent), pools[0].name, address(0), true);
        }

        Rewarder[] memory rewarders = abi.decode(config.parseRaw(".childRewarders"), (Rewarder[]));
        for (uint i; i < rewarders.length; ++i) {
            Rewarder memory rewarder = rewarders[i];

            ParentRewarderRolling parent = parentRewarders[rewarder.parentIndex];
            address rewarderAddress = parent.createChild(rewarder.rewardToken, tx.origin);
            rewarderAddresses.push(rewarderAddress);
        }
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
        } else {
            revert(string.concat("invalid token type ", poolTokenType));
        }
    }

    function _renounceRoles() internal {
        bytes32 defaultAdminRole = reliquary.DEFAULT_ADMIN_ROLE();
        reliquary.grantRole(defaultAdminRole, multisig);
        reliquary.grantRole(OPERATOR, multisig);
        reliquary.grantRole(EMISSION_CURVE, multisig);
        reliquary.renounceRole(OPERATOR, tx.origin);
        reliquary.renounceRole(defaultAdminRole, tx.origin);
        emissionCurve.transferOwnership(multisig);
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
