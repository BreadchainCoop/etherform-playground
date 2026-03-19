// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {SimpleNFT} from "../src/SimpleNFT.sol";
import {Marketplace} from "../src/Marketplace.sol";

contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        address nftProxy = Upgrades.deployTransparentProxy(
            "SimpleNFT.sol",
            deployer,
            abi.encodeCall(SimpleNFT.initialize, ("SimpleNFT", "SNFT", deployer))
        );
        console.log("SimpleNFT proxy:", nftProxy);

        address marketplaceProxy = Upgrades.deployTransparentProxy(
            "Marketplace.sol",
            deployer,
            abi.encodeCall(Marketplace.initialize, (deployer))
        );
        console.log("Marketplace proxy:", marketplaceProxy);

        vm.stopBroadcast();
    }
}
