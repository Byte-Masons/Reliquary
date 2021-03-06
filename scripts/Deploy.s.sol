// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "contracts/Reliquary.sol";
import "contracts/emission_curves/Constant.sol";
import "contracts/nft_descriptors/NFTDescriptorSingle4626.sol";
import "contracts/helpers/DepositHelper.sol";

contract Deploy is Script {
    uint[] wethCurve = [0, 1 days, 7 days, 14 days, 30 days, 90 days, 180 days, 365 days];
    uint[] wethLevels = [100, 120, 150, 200, 300, 400, 500, 750];

    bytes32 public constant OPERATOR = keccak256("OPERATOR");
    bytes32 public constant EMISSION_CURVE = keccak256("EMISSION_CURVE");

    address public constant MULTISIG = 0x111731A388743a75CF60CCA7b140C58e41D83635;

    Reliquary public reliquary;
    INFTDescriptor public nftDescriptor;
    DepositHelper public helper;

    function run() external {
        vm.createSelectFork("fantom");
        vm.startBroadcast();

        IERC20 oath = IERC20(0x21Ada0D2aC28C3A5Fa3cD2eE30882dA8812279B6);
        IEmissionCurve curve = IEmissionCurve(address(new Constant()));
        reliquary = new Reliquary(oath, curve);

        nftDescriptor = INFTDescriptor(address(new NFTDescriptorSingle4626(IReliquary(address(reliquary)))));

        IERC20 wethCrypt = IERC20(0x58C60B6dF933Ff5615890dDdDCdD280bad53f1C1);

        reliquary.grantRole(OPERATOR, tx.origin);
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
        reliquary.renounceRole(OPERATOR, tx.origin);
        reliquary.renounceRole(reliquary.DEFAULT_ADMIN_ROLE(), tx.origin);

        helper = new DepositHelper(address(reliquary));

        vm.stopBroadcast();
    }
}
