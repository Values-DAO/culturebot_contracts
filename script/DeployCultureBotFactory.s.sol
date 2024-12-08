//SPDX-License-Identifier:MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {CultureBotFactory} from "src/CultureBotFactory.sol";

import {console2} from "forge-std/console2.sol";

contract DeployCultureBotFactory is Script {
    function run() public returns (CultureBotFactory factory) {
        // Hardcoded parameters from the deployment example
        uint32 cw = 550000;
        address rToken = 0xC129124eA2Fd4D63C1Fc64059456D8f231eBbed1;

        // Deploy BancorFormula first (if not already deployed)
        address bancorFormula = 0xa05511D2bD497D8cDC27999f39F06c17c12dc5D0;

        // Start broadcast with the deployer's private key
        vm.startBroadcast();

        // Deploy CultureBotFactory with specified parameters
        factory = new CultureBotFactory(cw, rToken, bancorFormula);

        // Stop broadcasting
        vm.stopBroadcast();

        // Log the deployed contract addresses for verification
        console2.log("BancorFormula deployed at:", address(bancorFormula));
        console2.log("CultureBotFactory deployed at:", address(factory));
    }
}
