//SPDX-License-Identifier:MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {CultureBotFactory} from "src/ExponentialBC/CultureBotFactory.sol";

import {console2} from "forge-std/console2.sol";

contract DeployCultureBotFactory is Script {
    function run() public returns (CultureBotFactory factory) {
        // Start broadcast with the deployer's private key
        vm.startBroadcast();

        // Deploy CultureBotFactory with specified parameters
        factory = new CultureBotFactory();

        // Stop broadcasting
        vm.stopBroadcast();

        // Log the deployed contract addresses for verification

        console2.log("CultureBotFactory deployed at:", address(factory));
    }
}
