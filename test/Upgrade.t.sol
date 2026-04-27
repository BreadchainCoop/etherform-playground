// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {SimpleNFT} from "../src/SimpleNFT.sol";
import {SimpleNFTV2} from "../src/SimpleNFTV2.sol";
import {Marketplace} from "../src/Marketplace.sol";
import {MarketplaceV2} from "../src/MarketplaceV2.sol";

contract UpgradeTest is Test {
    SimpleNFT public nft;
    Marketplace public marketplace;
    address public nftProxy;
    address public marketplaceProxy;

    address public owner = makeAddr("owner");
    address public seller = makeAddr("seller");
    address public buyer;
    address public feeRecipient = makeAddr("feeRecipient");

    function setUp() public {
        buyer = makeAddr("buyer");
        vm.deal(buyer, 100 ether);

        nftProxy = Upgrades.deployTransparentProxy(
            "SimpleNFT.sol",
            owner,
            abi.encodeCall(SimpleNFT.initialize, ("SimpleNFT", "SNFT", owner))
        );
        nft = SimpleNFT(nftProxy);

        marketplaceProxy = Upgrades.deployTransparentProxy(
            "Marketplace.sol",
            owner,
            abi.encodeCall(Marketplace.initialize, (owner))
        );
        marketplace = Marketplace(marketplaceProxy);
    }

    // --- SimpleNFT upgrade ---

    function test_upgradeSimpleNFT_preservesState() public {
        vm.prank(owner);
        nft.safeMint(seller);

        Upgrades.upgradeProxy(
            nftProxy,
            "SimpleNFTV2.sol",
            abi.encodeCall(SimpleNFTV2.reinitialize, ("https://example.com/", 100)),
            owner
        );

        SimpleNFTV2 nftV2 = SimpleNFTV2(nftProxy);

        assertEq(nftV2.name(), "SimpleNFT");
        assertEq(nftV2.symbol(), "SNFT");
        assertEq(nftV2.ownerOf(0), seller);
        assertEq(nftV2.maxSupply(), 100);
    }

    function test_upgradeSimpleNFT_maxSupply() public {
        Upgrades.upgradeProxy(
            nftProxy,
            "SimpleNFTV2.sol",
            abi.encodeCall(SimpleNFTV2.reinitialize, ("https://example.com/", 2)),
            owner
        );

        SimpleNFTV2 nftV2 = SimpleNFTV2(nftProxy);

        vm.startPrank(owner);
        nftV2.safeMint(seller);
        nftV2.safeMint(seller);

        vm.expectRevert(SimpleNFTV2.MaxSupplyReached.selector);
        nftV2.safeMint(seller);
        vm.stopPrank();
    }

    function test_upgradeSimpleNFT_baseURI() public {
        vm.prank(owner);
        nft.safeMint(seller);

        Upgrades.upgradeProxy(
            nftProxy,
            "SimpleNFTV2.sol",
            abi.encodeCall(SimpleNFTV2.reinitialize, ("https://example.com/metadata/", 100)),
            owner
        );

        SimpleNFTV2 nftV2 = SimpleNFTV2(nftProxy);
        assertEq(nftV2.tokenURI(0), "https://example.com/metadata/0");
    }

    function test_upgradeSimpleNFT_reinitializerCannotBeCalledTwice() public {
        Upgrades.upgradeProxy(
            nftProxy,
            "SimpleNFTV2.sol",
            abi.encodeCall(SimpleNFTV2.reinitialize, ("https://example.com/", 100)),
            owner
        );

        SimpleNFTV2 nftV2 = SimpleNFTV2(nftProxy);

        vm.expectRevert();
        nftV2.reinitialize("https://other.com/", 200);
    }

    // --- Marketplace upgrade ---

    function test_upgradeMarketplace_preservesState() public {
        uint256 tokenId = _mintAndApprove(seller);
        vm.prank(seller);
        marketplace.listNFT(address(nft), tokenId, 1 ether);

        Upgrades.upgradeProxy(
            marketplaceProxy,
            "MarketplaceV2.sol",
            abi.encodeCall(MarketplaceV2.reinitialize, (250, feeRecipient)),
            owner
        );

        MarketplaceV2 marketplaceV2 = MarketplaceV2(marketplaceProxy);

        (address s,,,, bool active) = marketplaceV2.listings(0);
        assertEq(s, seller);
        assertTrue(active);
        assertEq(marketplaceV2.feePercentage(), 250);
        assertEq(marketplaceV2.feeRecipient(), feeRecipient);
    }

    function test_upgradeMarketplace_feeOnBuy() public {
        uint256 tokenId = _mintAndApprove(seller);
        vm.prank(seller);
        marketplace.listNFT(address(nft), tokenId, 1 ether);

        Upgrades.upgradeProxy(
            marketplaceProxy,
            "MarketplaceV2.sol",
            abi.encodeCall(MarketplaceV2.reinitialize, (250, feeRecipient)),
            owner
        );

        MarketplaceV2 marketplaceV2 = MarketplaceV2(marketplaceProxy);

        uint256 sellerBalBefore = seller.balance;

        vm.prank(buyer);
        marketplaceV2.buyNFT{value: 1 ether}(0);

        uint256 expectedFee = (1 ether * 250) / 10_000;
        uint256 expectedSellerProceeds = 1 ether - expectedFee;

        assertEq(seller.balance, sellerBalBefore + expectedSellerProceeds);
        assertEq(marketplaceV2.accumulatedFees(), expectedFee);
    }

    function test_upgradeMarketplace_withdrawFees() public {
        uint256 tokenId = _mintAndApprove(seller);
        vm.prank(seller);
        marketplace.listNFT(address(nft), tokenId, 1 ether);

        Upgrades.upgradeProxy(
            marketplaceProxy,
            "MarketplaceV2.sol",
            abi.encodeCall(MarketplaceV2.reinitialize, (250, feeRecipient)),
            owner
        );

        MarketplaceV2 marketplaceV2 = MarketplaceV2(marketplaceProxy);

        vm.prank(buyer);
        marketplaceV2.buyNFT{value: 1 ether}(0);

        uint256 fees = marketplaceV2.accumulatedFees();
        uint256 recipientBalBefore = feeRecipient.balance;

        vm.prank(feeRecipient);
        marketplaceV2.withdrawFees();

        assertEq(feeRecipient.balance, recipientBalBefore + fees);
        assertEq(marketplaceV2.accumulatedFees(), 0);
    }

    function test_upgradeMarketplace_withdrawFees_revert_notRecipient() public {
        Upgrades.upgradeProxy(
            marketplaceProxy,
            "MarketplaceV2.sol",
            abi.encodeCall(MarketplaceV2.reinitialize, (250, feeRecipient)),
            owner
        );

        MarketplaceV2 marketplaceV2 = MarketplaceV2(marketplaceProxy);

        vm.prank(seller);
        vm.expectRevert(MarketplaceV2.NotFeeRecipient.selector);
        marketplaceV2.withdrawFees();
    }

    function test_upgradeMarketplace_reinitializerCannotBeCalledTwice() public {
        Upgrades.upgradeProxy(
            marketplaceProxy,
            "MarketplaceV2.sol",
            abi.encodeCall(MarketplaceV2.reinitialize, (250, feeRecipient)),
            owner
        );

        MarketplaceV2 marketplaceV2 = MarketplaceV2(marketplaceProxy);

        vm.expectRevert();
        marketplaceV2.reinitialize(500, feeRecipient);
    }

    // --- Storage layout validation ---

    function test_validateUpgrade_SimpleNFT() public {
        Upgrades.validateUpgrade("SimpleNFTV2.sol", _optsWithRef("SimpleNFT.sol"));
    }

    function test_validateUpgrade_Marketplace() public {
        Upgrades.validateUpgrade("MarketplaceV2.sol", _optsWithRef("Marketplace.sol"));
    }

    // --- Helpers ---

    function _mintAndApprove(address to) internal returns (uint256) {
        vm.prank(owner);
        uint256 tokenId = nft.safeMint(to);
        vm.prank(to);
        nft.approve(address(marketplace), tokenId);
        return tokenId;
    }

    function _optsWithRef(string memory ref) internal pure returns (Options memory opts) {
        opts.referenceContract = ref;
    }
}

import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
