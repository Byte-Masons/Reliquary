pragma solidity ^0.8.0;

import "./OZ/token/ERC721/extensions/ERC721Enumerable.sol";

contract Memento is IERC721, ERC721Enumerable {

  constructor() ERC721("Reliquary Position", "Memento") { }

  uint private nonce;

  function mint(address to) internal returns (uint id) {
    id = nonce;
    nonce++;
    _safeMint(to, id);
  }

  function burn(uint tokenId) internal returns (bool) {
    _burn(tokenId);
    return true;
  }

}
