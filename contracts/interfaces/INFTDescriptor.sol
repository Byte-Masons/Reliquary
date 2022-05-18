// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import '../ReliquaryData.sol';

interface INFTDescriptor {
    function constructTokenURI(uint relicId, ReliquaryData.Level[] memory levels) external view returns (string memory);
}
