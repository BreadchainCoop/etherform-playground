// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {SimpleNFT} from "../src/SimpleNFT.sol";
import {Marketplace} from "../src/Marketplace.sol";

contract MarketplaceTest is Test {
    SimpleNFT public nft;
    Marketplace public marketplace;

    address public owner = makeAddr("owner");
    address public seller = makeAddr("seller");
    address public buyer;

    function setUp() public {
        buyer = makeAddr("buyer");
        vm.deal(buyer, 100 ether);

        address nftProxy = Upgrades.deployTransparentProxy(
            "SimpleNFT.sol", owner, abi.encodeCall(SimpleNFT.initialize, ("SimpleNFT", "SNFT", owner))
        );
        nft = SimpleNFT(nftProxy);

        address marketplaceProxy =
            Upgrades.deployTransparentProxy("Marketplace.sol", owner, abi.encodeCall(Marketplace.initialize, (owner)));
        marketplace = Marketplace(marketplaceProxy);
    }

    function _mintAndApprove(address to) internal returns (uint256) {
        vm.prank(owner);
        uint256 tokenId = nft.safeMint(to);
        vm.prank(to);
        nft.approve(address(marketplace), tokenId);
        return tokenId;
    }

    // --- listNFT ---

    function test_listNFT() public {
        uint256 tokenId = _mintAndApprove(seller);

        vm.prank(seller);
        uint256 listingId = marketplace.listNFT(address(nft), tokenId, 1 ether);

        assertEq(listingId, 0);
        assertEq(nft.ownerOf(tokenId), address(marketplace));

        (address s, address c, uint256 tid, uint256 price, bool active) = marketplace.listings(listingId);
        assertEq(s, seller);
        assertEq(c, address(nft));
        assertEq(tid, tokenId);
        assertEq(price, 1 ether);
        assertTrue(active);
    }

    function test_listNFT_emitsEvent() public {
        uint256 tokenId = _mintAndApprove(seller);

        vm.expectEmit(true, true, true, true);
        emit Marketplace.NFTListed(0, seller, address(nft), tokenId, 1 ether);

        vm.prank(seller);
        marketplace.listNFT(address(nft), tokenId, 1 ether);
    }

    function test_listNFT_revert_priceZero() public {
        uint256 tokenId = _mintAndApprove(seller);

        vm.prank(seller);
        vm.expectRevert(Marketplace.PriceCannotBeZero.selector);
        marketplace.listNFT(address(nft), tokenId, 0);
    }

    // --- buyNFT ---

    function test_buyNFT() public {
        uint256 tokenId = _mintAndApprove(seller);
        vm.prank(seller);
        uint256 listingId = marketplace.listNFT(address(nft), tokenId, 1 ether);

        uint256 sellerBalBefore = seller.balance;

        vm.prank(buyer);
        marketplace.buyNFT{value: 1 ether}(listingId);

        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(seller.balance, sellerBalBefore + 1 ether);

        (,,,, bool active) = marketplace.listings(listingId);
        assertFalse(active);
    }

    function test_buyNFT_refundsExcess() public {
        uint256 tokenId = _mintAndApprove(seller);
        vm.prank(seller);
        uint256 listingId = marketplace.listNFT(address(nft), tokenId, 1 ether);

        uint256 buyerBalBefore = buyer.balance;

        vm.prank(buyer);
        marketplace.buyNFT{value: 2 ether}(listingId);

        assertEq(buyer.balance, buyerBalBefore - 1 ether);
    }

    function test_buyNFT_emitsEvent() public {
        uint256 tokenId = _mintAndApprove(seller);
        vm.prank(seller);
        uint256 listingId = marketplace.listNFT(address(nft), tokenId, 1 ether);

        vm.expectEmit(true, true, false, true);
        emit Marketplace.NFTSold(listingId, buyer, 1 ether);

        vm.prank(buyer);
        marketplace.buyNFT{value: 1 ether}(listingId);
    }

    function test_buyNFT_revert_insufficientPayment() public {
        uint256 tokenId = _mintAndApprove(seller);
        vm.prank(seller);
        uint256 listingId = marketplace.listNFT(address(nft), tokenId, 1 ether);

        vm.prank(buyer);
        vm.expectRevert(Marketplace.InsufficientPayment.selector);
        marketplace.buyNFT{value: 0.5 ether}(listingId);
    }

    function test_buyNFT_revert_listingNotActive() public {
        uint256 tokenId = _mintAndApprove(seller);
        vm.prank(seller);
        uint256 listingId = marketplace.listNFT(address(nft), tokenId, 1 ether);

        vm.prank(buyer);
        marketplace.buyNFT{value: 1 ether}(listingId);

        vm.prank(buyer);
        vm.expectRevert(Marketplace.ListingNotActive.selector);
        marketplace.buyNFT{value: 1 ether}(listingId);
    }

    // --- cancelListing ---

    function test_cancelListing() public {
        uint256 tokenId = _mintAndApprove(seller);
        vm.prank(seller);
        uint256 listingId = marketplace.listNFT(address(nft), tokenId, 1 ether);

        vm.prank(seller);
        marketplace.cancelListing(listingId);

        assertEq(nft.ownerOf(tokenId), seller);

        (,,,, bool active) = marketplace.listings(listingId);
        assertFalse(active);
    }

    function test_cancelListing_emitsEvent() public {
        uint256 tokenId = _mintAndApprove(seller);
        vm.prank(seller);
        uint256 listingId = marketplace.listNFT(address(nft), tokenId, 1 ether);

        vm.expectEmit(true, false, false, false);
        emit Marketplace.ListingCancelled(listingId);

        vm.prank(seller);
        marketplace.cancelListing(listingId);
    }

    function test_cancelListing_revert_notSeller() public {
        uint256 tokenId = _mintAndApprove(seller);
        vm.prank(seller);
        uint256 listingId = marketplace.listNFT(address(nft), tokenId, 1 ether);

        vm.prank(buyer);
        vm.expectRevert(Marketplace.NotSeller.selector);
        marketplace.cancelListing(listingId);
    }

    function test_cancelListing_revert_alreadyCancelled() public {
        uint256 tokenId = _mintAndApprove(seller);
        vm.prank(seller);
        uint256 listingId = marketplace.listNFT(address(nft), tokenId, 1 ether);

        vm.prank(seller);
        marketplace.cancelListing(listingId);

        vm.prank(seller);
        vm.expectRevert(Marketplace.ListingNotActive.selector);
        marketplace.cancelListing(listingId);
    }

    function test_buyNFT_revert_afterCancel() public {
        uint256 tokenId = _mintAndApprove(seller);
        vm.prank(seller);
        uint256 listingId = marketplace.listNFT(address(nft), tokenId, 1 ether);

        vm.prank(seller);
        marketplace.cancelListing(listingId);

        vm.prank(buyer);
        vm.expectRevert(Marketplace.ListingNotActive.selector);
        marketplace.buyNFT{value: 1 ether}(listingId);
    }
}
