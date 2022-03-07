// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface INFTDescriptor {
    struct ConstructTokenURIParams {
        uint256 tokenId;
        uint256 poolId;
        bool isLP;
        string poolName;
        address underlying;
        uint256 amount;
        uint256 pendingOath;
        uint256 maturity;
        address curveAddress;
    }

    function constructTokenURI(ConstructTokenURIParams memory params) external view returns (string memory);
}
