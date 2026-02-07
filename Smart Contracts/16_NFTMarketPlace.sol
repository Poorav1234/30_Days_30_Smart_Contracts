// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTMarketplace is ReentrancyGuard, Ownable {

    uint256 public marketplaceFee;
    uint256 public listingIdCounter;

    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;
        address creator;
        uint256 royalty;
        bool active;
    }

    mapping(uint256 => Listing) public listings;
    
    event NFTListed(
        uint256 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 price
    );

    event NFTSold(
        uint256 indexed listingId,
        address buyer,
        uint256 price
    );

    event ListingCancelled(
        uint256 indexed listingId
    );

    constructor(uint256 _marketplaceFee) Ownable(msg.sender) {
        marketplaceFee = _marketplaceFee;
    }

    function listNFT(
        address _nftContract,
        uint256 _tokenId,
        uint256 _price,
        address _creator,
        uint256 _royalty
    ) external nonReentrant {

        require(_price > 0, "Price must be > 0");
        require(_royalty <= 20, "Royalty too high");

        IERC721 nft = IERC721(_nftContract);

        require(nft.ownerOf(_tokenId) == msg.sender,"Not NFT owner");

        nft.transferFrom(msg.sender, address(this), _tokenId);

        listingIdCounter++;

        listings[listingIdCounter] = Listing({
            seller: msg.sender,
            nftContract: _nftContract,
            tokenId: _tokenId,
            price: _price,
            creator: _creator,
            royalty: _royalty,
            active: true
        });

        emit NFTListed(listingIdCounter, msg.sender, _nftContract, _tokenId, _price);
    }

    function buyNFT(uint256 _listingId)
        external
        payable
        nonReentrant
    {
        Listing storage item = listings[_listingId];

        require(item.active, "Listing inactive");
        require(msg.value == item.price, "Incorrect ETH");

        item.active = false;
        uint256 royaltyAmount = (item.price * item.royalty) / 100;
        uint256 feeAmount = (item.price * marketplaceFee) / 100;
        uint256 sellerAmount = item.price - royaltyAmount - feeAmount;

        if (royaltyAmount > 0) {
            payable(item.creator).transfer(royaltyAmount);
        }

        if (feeAmount > 0) {
            payable(owner()).transfer(feeAmount);
        }

        payable(item.seller).transfer(sellerAmount);
        IERC721(item.nftContract).transferFrom(
            address(this),
            msg.sender,
            item.tokenId
        );

        emit NFTSold(_listingId, msg.sender, item.price);
    }

    function cancelListing(uint256 _listingId) external nonReentrant
    {
        Listing storage item = listings[_listingId];

        require(item.active, "Already inactive");
        require(item.seller == msg.sender, "Not seller");
        item.active = false;
        IERC721(item.nftContract).transferFrom(
            address(this),
            msg.sender,
            item.tokenId
        );
        emit ListingCancelled(_listingId);
    }

    function updateMarketplaceFee(uint256 _newFee) external onlyOwner
    {
        require(_newFee <= 10, "Fee too high");
        marketplaceFee = _newFee;
    }

    function withdrawETH() external onlyOwner
    {
        payable(owner()).transfer(address(this).balance);
    }
}