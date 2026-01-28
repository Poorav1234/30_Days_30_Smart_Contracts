// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract NFTMintingERC721 {

    string public name = "MYNFT";
    string public symbol = "NFT";

    uint public tokenID = 0;
    mapping(uint => address) private ownerCheck;
    mapping(address => uint) private balanceCheck;
    mapping(uint => string) private tokenURI;

    event transferEvent(address indexed from, address indexed to, uint indexed tokenID);

    function mint(string memory tokenURIValue) public {
        tokenID++;
        uint newID = tokenID;

        ownerCheck[newID] = msg.sender;
        balanceCheck[msg.sender]++;
        tokenURI[newID] = tokenURIValue;

        emit transferEvent(address(0), msg.sender, newID);
    }

    function ownerOfToken(uint tokenIDValue) public view returns (address) {
        address owner = ownerCheck[tokenIDValue];
        require(owner != address(0), "NFT doesn't exist");
        return owner;
    }

    function balanceOfOwner(address ownerAddress) public view returns (uint) {
        require(ownerAddress != address(0), "Invalid address");
        return balanceCheck[ownerAddress];
    }

    function tokenContent(uint tokenIDValue) public view returns (string memory) {
        require(ownerCheck[tokenIDValue] != address(0), "NFT does not exist");
        return tokenURI[tokenIDValue];
    }

    function transferFrom(address from, address to, uint tokenIDValue) public {
        require(ownerCheck[tokenIDValue] == from, "Not NFT owner");
        require(to != address(0), "Invalid address");
        require(msg.sender == from, "Not authorized");

        balanceCheck[from]--;
        balanceCheck[to]++;
        ownerCheck[tokenIDValue] = to;

        emit transferEvent(from, to, tokenIDValue);
    }
}
