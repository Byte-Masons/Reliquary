// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface INFTDescriptor {
    struct Level {
        uint256 requiredMaturity;
        uint256 allocPoint;
    }

    struct ConstructTokenURIParams {
        uint256 tokenId;
        uint256 poolId;
        bool isPair;
        string poolName;
        address underlying;
        uint256 amount;
        uint256 pendingOath;
        uint256 maturity;
	uint256 level;
        Level[] levels;
    }

    function constructTokenURI(ConstructTokenURIParams memory params) external view returns (string memory);
}
