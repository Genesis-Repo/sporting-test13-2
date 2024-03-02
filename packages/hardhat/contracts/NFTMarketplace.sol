// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTMarketplace is ERC721Holder, Ownable {
    uint256 public feePercentage;   // Fee percentage to be set by the marketplace owner
    uint256 private constant PERCENTAGE_BASE = 100;

    struct Listing {
        address seller;
        uint256 price;
        bool isActive;
        bool isAuction;  // New field to check if the listing is an auction
        uint256 highestBid;
        address highestBidder;
    }

    mapping(address => mapping(uint256 => Listing)) private listings;

    event NFTListed(address indexed seller, uint256 indexed tokenId, uint256 price);
    event NFTSold(address indexed seller, address indexed buyer, uint256 indexed tokenId, uint256 price);
    event NFTPriceChanged(address indexed seller, uint256 indexed tokenId, uint256 newPrice);
    event NFTUnlisted(address indexed seller, uint256 indexed tokenId);
    event NFTBidPlaced(address indexed bidder, uint256 indexed tokenId, uint256 amount);
    event NFTAuctionEnded(address indexed seller, address indexed winner, uint256 indexed tokenId, uint256 price);

    // Constructor to set the default fee percentage
    constructor() {
        feePercentage = 2;  // Setting the default fee percentage to 2%
    }

    // Function to list an NFT for sale with an auction
    function listNFTForAuction(address nftContract, uint256 tokenId, uint256 startingPrice) external {
        require(startingPrice > 0, "Starting price must be greater than zero");

        // Transfer the NFT from the seller to the marketplace contract
        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);

        // Create a new auction listing
        listings[nftContract][tokenId] = Listing({
            seller: msg.sender,
            price: startingPrice,
            isActive: true,
            isAuction: true,
            highestBid: startingPrice,
            highestBidder: address(0)
        });

        emit NFTListed(msg.sender, tokenId, startingPrice);
    }

    // Function for users to place bids on an auction
    function placeBid(address nftContract, uint256 tokenId) external payable {
        Listing storage listing = listings[nftContract][tokenId];
        require(listing.isAuction, "NFT is not listed for auction");
        require(msg.value > listing.highestBid, "Bid must be higher than current highest bid");

        if (listing.highestBidder != address(0)) {
            payable(listing.highestBidder).transfer(listing.highestBid); // Refund the previous highest bidder
        }

        listing.highestBid = msg.value;
        listing.highestBidder = msg.sender;

        emit NFTBidPlaced(msg.sender, tokenId, msg.value);
    }

    // Function to end the auction and finalize the highest bidder
    function endAuction(address nftContract, uint256 tokenId) external {
        Listing storage listing = listings[nftContract][tokenId];
        require(listing.isAuction, "NFT is not listed for auction");
        require(msg.sender == listing.seller, "Only the seller can end the auction");

        uint256 winningBid = listing.highestBid;

        // Transfer the NFT to the highest bidder
        IERC721(nftContract).safeTransferFrom(address(this), listing.highestBidder, tokenId);

        // Calculate and transfer the fee to the marketplace owner
        uint256 feeAmount = (winningBid * feePercentage) / PERCENTAGE_BASE;
        uint256 sellerAmount = winningBid - feeAmount;
        payable(owner()).transfer(feeAmount); // Transfer fee to marketplace owner

        // Transfer the remaining amount to the seller
        payable(listing.seller).transfer(sellerAmount);

        // Update the listing
        listing.isActive = false;

        emit NFTAuctionEnded(listing.seller, listing.highestBidder, tokenId, winningBid);
    }

    // Additional features can be added here

    // Function to change the price of a listed NFT
    function changePrice(address nftContract, uint256 tokenId, uint256 newPrice) external {
        require(newPrice > 0, "Price must be greater than zero");
        require(listings[nftContract][tokenId].seller == msg.sender, "You are not the seller");

        listings[nftContract][tokenId].price = newPrice;

        emit NFTPriceChanged(msg.sender, tokenId, newPrice);
    }

    // Function to unlist a listed NFT
    function unlistNFT(address nftContract, uint256 tokenId) external {
        require(listings[nftContract][tokenId].seller == msg.sender, "You are not the seller");

        delete listings[nftContract][tokenId];

        // Transfer the NFT back to the seller
        IERC721(nftContract).safeTransferFrom(address(this), msg.sender, tokenId);

        emit NFTUnlisted(msg.sender, tokenId);
    }

    // Function to set the fee percentage by the marketplace owner
    function setFeePercentage(uint256 newFeePercentage) external onlyOwner {
        require(newFeePercentage < PERCENTAGE_BASE, "Fee percentage must be less than 100");

        feePercentage = newFeePercentage;
    }
}