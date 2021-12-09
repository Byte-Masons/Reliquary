pragma solidity ^0.8.0;

import "./OZ/token/ERC721/extensions/ERC721Enumerable.sol";

contract Memento is IERC721, ERC721Enumerable {

  constructor() ERC721("Reliquary Position", "Memento") { }

  mapping (uint => uint) public nonces;

  function createId(uint pid) internal returns (uint256) {
    uint id = uint256(keccak256(abi.encodePacked(pid, nonces[pid])));
    nonces[pid]++;
    return id;
  }

  function mint(address to, uint pid) internal returns (uint) {
    uint id = createId(pid);
    _safeMint(to, id);
    return id;
  }

  function burn(uint tokenId) internal returns (bool) {
    _burn(tokenId);
    return true;
  }

}
