// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface INFTDescriptor {
    struct Level {
        uint requiredMaturity;
        uint allocPoint;
    }

    struct ConstructTokenURIParams {
        uint tokenId;
        uint poolId;
        bool isPair;
        string poolName;
        address underlying;
        uint amount;
        uint pendingOath;
        uint maturity;
        uint level;
        Level[] levels;
    }

    function constructTokenURI(ConstructTokenURIParams memory params) external view returns (string memory);
}
