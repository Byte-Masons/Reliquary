// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "contracts/Reliquary.sol";
import "contracts/emission_curves/Constant.sol";
import "contracts/nft_descriptors/NFTDescriptorSingle4626.sol";

contract Deploy is Script {
    uint[] wethCurve = [0, 1 days, 7 days, 14 days, 30 days, 90 days, 180 days, 365 days];
    uint[] wethLevels = [100, 120, 150, 200, 300, 400, 500, 750];

    bytes32 constant OPERATOR = keccak256("OPERATOR");
    bytes32 constant EMISSION_CURVE = keccak256("EMISSION_CURVE");

    address constant MULTISIG = address(0x111731A388743a75CF60CCA7b140C58e41D83635);

    function run() external {
        vm.createSelectFork("fantom");
        vm.startBroadcast();

        IERC20 oath = IERC20(0x21Ada0D2aC28C3A5Fa3cD2eE30882dA8812279B6);
        IEmissionCurve curve = IEmissionCurve(address(new Constant()));
        Reliquary reliquary = new Reliquary(oath, curve);

        INFTDescriptor nftDescriptor = INFTDescriptor(address(new NFTDescriptor(IReliquary(address(reliquary)))));

        IERC20 wethCrypt = IERC20(0x58C60B6dF933Ff5615890dDdDCdD280bad53f1C1);

        reliquary.grantRole(OPERATOR, msg.sender);
        reliquary.addPool(
            100,
            wethCrypt,
            IRewarder(address(0)),
            wethCurve,
            wethLevels,
            "ETH Pool",
            nftDescriptor
        );

        reliquary.grantRole(reliquary.DEFAULT_ADMIN_ROLE(), MULTISIG);
        reliquary.grantRole(OPERATOR, MULTISIG);
        reliquary.grantRole(EMISSION_CURVE, MULTISIG);
        reliquary.renounceRole(OPERATOR, msg.sender);
        reliquary.renounceRole(reliquary.DEFAULT_ADMIN_ROLE(), msg.sender);

        vm.stopBroadcast();
    }
}
