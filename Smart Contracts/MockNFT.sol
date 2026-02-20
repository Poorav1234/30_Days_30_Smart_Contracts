// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/*
    Simple NFT Contract (ERC-721) 
    - Owner can mint NFTs to any address
    - Token IDs auto-increment (0,1,2,...)
    - Good for Remix testing
*/

contract MockNFT is ERC721, Ownable {
    uint256 public nextTokenId;

    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) Ownable(msg.sender) {}

    // Owner mints an NFT to any address
    function mint(address to) external onlyOwner returns (uint256 tokenId) {
        tokenId = nextTokenId;
        nextTokenId++;
        _safeMint(to, tokenId);
    }
}