// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract ValidateUpgrade is Script {
    function run() external {
        Options memory opts;
        opts.referenceContract = "SimpleNFT.sol";
        Upgrades.validateUpgrade("SimpleNFTV2.sol", opts);
        console.log("SimpleNFT -> SimpleNFTV2 upgrade: VALID");

        opts.referenceContract = "Marketplace.sol";
        Upgrades.validateUpgrade("MarketplaceV2.sol", opts);
        console.log("Marketplace -> MarketplaceV2 upgrade: VALID");
    }
}
