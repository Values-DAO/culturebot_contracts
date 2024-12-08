//SPDX-License-Identifier:MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";

import {BancorFormula} from "src/BancorFormula/BancorFormula.sol";
import {console2} from "forge-std/console2.sol";

contract DeployBancorFormula is Script {
    function run() public returns (BancorFormula bancorFormula) {
        // Deploy BancorFormula first (if not already deployed)

        // Start broadcast with the deployer's private key
        vm.startBroadcast();
        bancorFormula = new BancorFormula();

        // Stop broadcasting
        vm.stopBroadcast();

        // Log the deployed contract addresses for verification
        console2.log("BancorFormula deployed at:", address(bancorFormula));
    }
}
