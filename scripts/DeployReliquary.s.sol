// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Reliquary} from "contracts/Reliquary.sol";
import {OwnableCurve} from "contracts/emission_curves/OwnableCurve.sol";
import {DepositHelperERC4626} from "contracts/helpers/DepositHelperERC4626.sol";
import {NFTDescriptor, NFTDescriptorPair} from "contracts/nft_descriptors/NFTDescriptorPair.sol";
import {NFTDescriptorSingle4626} from "contracts/nft_descriptors/NFTDescriptorSingle4626.sol";
import {ParentRewarderRolling, RollingRewarder} from "contracts/rewarders/ParentRewarder-Rolling.sol";

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
    bytes32 constant EMISSION_CURVE = keccak256("EMISSION_CURVE");
    bytes32 constant CHILD_SETTER = keccak256("CHILD_SETTER");
    bytes32 constant REWARD_SETTER = keccak256("REWARD_SETTER");

    string config;
    address multisig;
    Reliquary reliquary;
    OwnableCurve emissionCurve;
    mapping (uint => address) rewarderForPoolId;
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

            address rewarder;
            if (pool.childRewarderTokens.length > 0) {
                rewarder = address(new ParentRewarderRolling(address(reliquary), i));
                rewarderForPoolId[i] = rewarder;
            }

            reliquary.addPool(
                pool.allocPoint,
                pool.poolToken,
                rewarder,
                pool.requiredMaturities,
                pool.levelMultipliers,
                pool.name,
                nftDescriptor,
                pool.allowPartialWithdrawals
            );
        }

        _deployChildRewarders();

        if (multisig != address(0)) {
            _renounceRoles();
        }

        vm.stopBroadcast();
    }

    function _deployChildRewarders() internal {
        Pool[] memory pools = abi.decode(config.parseRaw(".pools"), (Pool[]));
        for (uint i; i < pools.length; ++i) {
            Pool memory pool = pools[i];
            if (pools[i].childRewarderTokens.length == 0) {
                continue;
            }
            ParentRewarderRolling parent = ParentRewarderRolling(rewarderForPoolId[i]);

            parent.grantRole(CHILD_SETTER, tx.origin);
            parent.grantRole(REWARD_SETTER, tx.origin);
            parentRewarders.push(parent);

            require(pool.childRewarderTokens.length == pool.childRewarderPeriods.length, "invalid child rewarder data");

            for (uint j; j < pool.childRewarderTokens.length; ++j) {
                address rewardToken = pool.childRewarderTokens[j];
                uint period = pool.childRewarderPeriods[j];
                RollingRewarder child = RollingRewarder(parent.createChild(rewardToken, tx.origin));
                child.updateDistributionPeriod(period);
                if (multisig != address(0)) child.transferOwnership(multisig);
            }
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
