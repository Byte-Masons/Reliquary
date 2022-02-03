// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface INFTDescriptor {
    function constructTokenURI(
        uint256 tokenId,
        string memory underlying,
        uint256 poolId,
        uint256 amount,
        uint256 pendingOath,
        uint256 entry,
        address curveAddress
    ) external pure returns (string memory);
}
