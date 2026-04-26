// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {SimpleNFT} from "../src/SimpleNFT.sol";

contract SimpleNFTTest is Test {
    SimpleNFT public nft;
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        address proxy = Upgrades.deployTransparentProxy(
            "SimpleNFT.sol", owner, abi.encodeCall(SimpleNFT.initialize, ("SimpleNFT", "SNFT", owner))
        );
        nft = SimpleNFT(proxy);
    }

    function test_initialize() public view {
        assertEq(nft.name(), "SimpleNFT");
        assertEq(nft.symbol(), "SNFT");
        assertEq(nft.owner(), owner);
    }

    function test_safeMint() public {
        vm.prank(owner);
        uint256 tokenId = nft.safeMint(user);

        assertEq(tokenId, 0);
        assertEq(nft.ownerOf(0), user);
    }

    function test_safeMint_incrementsTokenId() public {
        vm.startPrank(owner);
        assertEq(nft.safeMint(user), 0);
        assertEq(nft.safeMint(user), 1);
        assertEq(nft.safeMint(user), 2);
        vm.stopPrank();

        assertEq(nft.balanceOf(user), 3);
    }

    function test_safeMint_revert_notOwner() public {
        vm.prank(user);
        vm.expectRevert();
        nft.safeMint(user);
    }
}
