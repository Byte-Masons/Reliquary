// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Reliquary} from "contracts/Reliquary.sol";
import {ICurves, LinearCurve} from "contracts/curves/LinearCurve.sol";
import {LinearPlateauCurve} from "contracts/curves/LinearPlateauCurve.sol";
import {DepositHelperERC4626} from "contracts/helpers/DepositHelperERC4626.sol";
import {NFTDescriptor, NFTDescriptorPair} from "contracts/nft_descriptors/NFTDescriptorPair.sol";
import {NFTDescriptorSingle4626} from "contracts/nft_descriptors/NFTDescriptorSingle4626.sol";
import {ParentRollingRewarder} from "contracts/rewarders/ParentRollingRewarder.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Deploy is Script {
    using stdJson for string;

    struct Pool {
        uint256 allocPoint;
        bool allowPartialWithdrawals;
        uint256 curveIndex;
        string curveType;
        string name;
        address poolToken;
        string tokenType;
    }

    struct ParentRewarderParams {
        uint256 poolId;
    }

    struct ChildRewarderParams {
        uint256 parentIndex;
        address rewarderToken;
    }

    struct LinearCurveParams {
        uint256 minMultiplier;
        uint256 slope;
    }

    struct LinearPlateauCurveParams {
        uint256 minMultiplier;
        uint256 plateauLevel;
        uint256 slope;
    }

    bytes32 constant OPERATOR = keccak256("OPERATOR");
    bytes32 constant EMISSION_RATE = keccak256("EMISSION_RATE");

    string config;
    address multisig;
    address gaugeRewardReceiver;
    address voter;
    address bootstrapAdd;
    Reliquary reliquary;
    uint256 poolCount;
    address rewardToken;
    mapping(uint256 => ParentRollingRewarder) parentForPoolId;
    LinearCurve[] linearCurves;
    LinearPlateauCurve[] linearPlateauCurves;
    address nftDescriptorNormal;
    address nftDescriptor4626;
    address nftDescriptorPair;
    address depositHelper4626;

    function run() external {
        config = vm.readFile("scripts/deploy_conf.json");
        string memory name = config.readString(".name");
        string memory symbol = config.readString(".symbol");
        multisig = config.readAddress(".multisig");
        gaugeRewardReceiver = config.readAddress(".gaugeRewardReceiver");
        voter = config.readAddress(".voter");
        bootstrapAdd = config.readAddress(".multisig"); //! bootstrapAdd set to multisig.
        rewardToken = config.readAddress(".rewardToken");
        uint256 emissionRate = config.readUint(".emissionRate");
        Pool[] memory pools = abi.decode(config.parseRaw(".pools"), (Pool[]));
        poolCount = pools.length;

        vm.startBroadcast();

        _deployCurves();

        reliquary = new Reliquary(rewardToken, emissionRate, gaugeRewardReceiver, voter, name, symbol);

        _deployRewarders();

        reliquary.grantRole(OPERATOR, tx.origin);
        for (uint256 i = 0; i < pools.length; ++i) {
            Pool memory pool = pools[i];

            ICurves curve;
            bytes32 curveTypeHash = keccak256(bytes(pool.curveType));
            if (curveTypeHash == keccak256("linearCurve")) {
                curve = linearCurves[pool.curveIndex];
            } else if (curveTypeHash == keccak256("linearPlateauCurve")) {
                curve = linearPlateauCurves[pool.curveIndex];
            } else {
                revert(string.concat("invalid curve type ", pool.curveType));
            }

            address nftDescriptor = _deployHelpers(pool.tokenType);

            ERC20(pool.poolToken).approve(address(reliquary), 1); // approve 1 wei to bootstrap the pool
            reliquary.addPool(
                pool.allocPoint,
                pool.poolToken,
                address(parentForPoolId[i]),
                curve,
                pool.name,
                nftDescriptor,
                pool.allowPartialWithdrawals,
                bootstrapAdd
            );
        }

        if (multisig != address(0)) {
            _renounceRoles();
        }

        vm.stopBroadcast();
    }

    function _deployRewarders() internal {
        ParentRewarderParams[] memory parentParams =
            abi.decode(config.parseRaw(".parentRewarders"), (ParentRewarderParams[]));
        ParentRollingRewarder[] memory parentRewarders =
            new ParentRollingRewarder[](parentParams.length);
        for (uint256 i; i < parentParams.length; ++i) {
            ParentRewarderParams memory params = parentParams[i];

            ParentRollingRewarder newParent = new ParentRollingRewarder();

            parentRewarders[i] = newParent;
            parentForPoolId[params.poolId] = newParent;
        }

        ChildRewarderParams[] memory children =
            abi.decode(config.parseRaw(".childRewarders"), (ChildRewarderParams[]));
        for (uint256 i; i < children.length; ++i) {
            ChildRewarderParams memory child = children[i];
            ParentRollingRewarder parent = ParentRollingRewarder(parentRewarders[child.parentIndex]);
            parent.createChild(child.rewarderToken);
        }
    }

    function _deployCurves() internal {
        LinearCurveParams[] memory linearCurveParams =
            abi.decode(config.parseRaw(".linearCurves"), (LinearCurveParams[]));
        for (uint256 i; i < linearCurveParams.length; ++i) {
            LinearCurveParams memory params = linearCurveParams[i];
            linearCurves.push(new LinearCurve(params.slope, params.minMultiplier));
        }

        LinearPlateauCurveParams[] memory linearPlateauCurveParams =
            abi.decode(config.parseRaw(".linearPlateauCurves"), (LinearPlateauCurveParams[]));
        for (uint256 i; i < linearPlateauCurveParams.length; ++i) {
            LinearPlateauCurveParams memory params = linearPlateauCurveParams[i];
            linearPlateauCurves.push(
                new LinearPlateauCurve(params.slope, params.minMultiplier, params.plateauLevel)
            );
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
                depositHelper4626 =
                    address(new DepositHelperERC4626(reliquary, config.readAddress(".weth")));
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
        reliquary.grantRole(EMISSION_RATE, multisig);
        reliquary.renounceRole(OPERATOR, tx.origin);
        reliquary.renounceRole(defaultAdminRole, tx.origin);
        if (multisig != address(0)) {
            for (uint256 i; i < poolCount; ++i) {
                if (address(parentForPoolId[i]) != address(0)) {
                    parentForPoolId[i].transferOwnership(multisig);
                }
            }
        }
    }
}
