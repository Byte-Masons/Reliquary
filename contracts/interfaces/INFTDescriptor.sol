// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface INFTDescriptor {
    function constructTokenURI(uint relicId) external view returns (string memory);
}
