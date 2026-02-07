// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TestNFT is ERC721, Ownable {
    uint256 public tokenId;

    constructor()
        ERC721("TestNFT", "TNFT")
        Ownable(msg.sender)
    {}

    function mint() external {
        tokenId++;
        _mint(msg.sender, tokenId);
    }
}
