// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface INFTDescriptor {
    function constructTokenURI(uint256 _relicId) external view returns (string memory);
}
