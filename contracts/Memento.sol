pragma solidity ^0.8.0;

import "./OZ/token/ERC721/ERC721.sol";

contract Memento is ERC721("Relic Position", "MEMENTO") {

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
