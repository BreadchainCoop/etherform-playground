// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @custom:oz-upgrades-from Marketplace
contract MarketplaceV2 is OwnableUpgradeable, ReentrancyGuardTransient {
    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;
        bool active;
    }

    uint256 private _nextListingId;
    mapping(uint256 => Listing) public listings;
    mapping(address => mapping(uint256 => uint256)) private _activeListingId;

    // --- V2 storage (appended) ---
    uint256 public feePercentage;
    address public feeRecipient;
    uint256 public accumulatedFees;
    uint256 public test;

    event NFTListed(
        uint256 indexed listingId, address indexed seller, address indexed nftContract, uint256 tokenId, uint256 price
    );
    event NFTSold(uint256 indexed listingId, address indexed buyer, uint256 price);
    event ListingCancelled(uint256 indexed listingId);

    error PriceCannotBeZero();
    error ListingNotActive();
    error InsufficientPayment();
    error NotSeller();
    error TransferFailed();
    error NotFeeRecipient();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner) external initializer {
        __Ownable_init(owner);
    }

    function reinitialize(uint256 _feePercentage, address _feeRecipient) external reinitializer(2) {
        feePercentage = _feePercentage;
        feeRecipient = _feeRecipient;
    }

    function listNFT(address nftContract, uint256 tokenId, uint256 price) external returns (uint256) {
        if (price == 0) revert PriceCannotBeZero();

        IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);

        uint256 listingId = _nextListingId++;
        listings[listingId] =
            Listing({seller: msg.sender, nftContract: nftContract, tokenId: tokenId, price: price, active: true});
        _activeListingId[nftContract][tokenId] = listingId;

        emit NFTListed(listingId, msg.sender, nftContract, tokenId, price);
        return listingId;
    }

    function buyNFT(uint256 listingId) external payable nonReentrant {
        Listing storage listing = listings[listingId];
        if (!listing.active) revert ListingNotActive();
        if (msg.value < listing.price) revert InsufficientPayment();

        listing.active = false;
        delete _activeListingId[listing.nftContract][listing.tokenId];

        uint256 fee = (listing.price * feePercentage) / 10_000;
        uint256 sellerProceeds = listing.price - fee;
        accumulatedFees += fee;

        IERC721(listing.nftContract).transferFrom(address(this), msg.sender, listing.tokenId);

        (bool success,) = listing.seller.call{value: sellerProceeds}("");
        if (!success) revert TransferFailed();

        uint256 refund = msg.value - listing.price;
        if (refund > 0) {
            (bool refundSuccess,) = msg.sender.call{value: refund}("");
            if (!refundSuccess) revert TransferFailed();
        }

        emit NFTSold(listingId, msg.sender, listing.price);
    }

    function cancelListing(uint256 listingId) external {
        Listing storage listing = listings[listingId];
        if (!listing.active) revert ListingNotActive();
        if (msg.sender != listing.seller) revert NotSeller();

        listing.active = false;
        delete _activeListingId[listing.nftContract][listing.tokenId];

        IERC721(listing.nftContract).transferFrom(address(this), listing.seller, listing.tokenId);

        emit ListingCancelled(listingId);
    }

    function withdrawFees() external {
        if (msg.sender != feeRecipient) revert NotFeeRecipient();
        uint256 amount = accumulatedFees;
        accumulatedFees = 0;

        (bool success,) = feeRecipient.call{value: amount}("");
        if (!success) revert TransferFailed();
    }
}
