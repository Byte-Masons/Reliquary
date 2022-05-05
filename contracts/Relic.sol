// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

// The NFT
abstract contract Relic is IERC721, ERC721Enumerable {
    constructor() ERC721("Reliquary Liquidity Position", "RELIC") {}

    uint256 private nonce;

    function mint(address to) internal returns (uint256 id) {
        id = nonce++;
        _safeMint(to, id);
    }

    function burn(uint256 tokenId) internal returns (bool) {
        _burn(tokenId);
        return true;
    }
}
