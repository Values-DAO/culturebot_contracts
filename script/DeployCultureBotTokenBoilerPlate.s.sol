//SPDX-License-Identifier:MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";

import {BancorFormula} from "src/Bancor/BancorFormula/BancorFormula.sol";
import {console2} from "forge-std/console2.sol";
import {CultureBotTokenBoilerPlate} from "src/Bancor/CultureBotTokenBoilerPlate.sol";

contract DeployCultureBotToken is Script {
    uint256 constant MAXIMUM_SUPPLY = 100000000000;

    uint256 public constant TREASURY_ALLOCATION = (9 * MAXIMUM_SUPPLY) / 100;
    uint256 public constant ADMIN_ALLOCATION = (1 * MAXIMUM_SUPPLY) / 100;

    address[] allocationAddresses = new address[](3);
    uint256[] allocationAmounts = new uint256[](3);
    string name_ = "Anoother Token";
    string symbol_ = "ATK";
    address factory = 0x6125E6895a1D9e291684180297f8a7932D22f598;

    function run()
        public
        returns (CultureBotTokenBoilerPlate tokenBoilerPlate)
    {
        allocationAddresses[0] = 0xE6F3889C8EbB361Fa914Ee78fa4e55b1BBed3A96;
        allocationAddresses[1] = 0xeE6bA7cd79BB52D2e0947b86155743b22dB78eaE;
        allocationAddresses[2] = 0x6aA95bf77616b89658F98e50390F6514214FE536;

        allocationAmounts[0] = 4500000000;
        allocationAmounts[1] = 4500000000;
        allocationAmounts[2] = 1000000000;

        // Start broadcast with the deployer's private key
        vm.startBroadcast();
        tokenBoilerPlate = new CultureBotTokenBoilerPlate(
            name_,
            symbol_,
            MAXIMUM_SUPPLY,
            allocationAddresses,
            allocationAmounts,
            factory
        );

        // Stop broadcasting
        vm.stopBroadcast();

        // Log the deployed contract addresses for verification
        console2.log("BancorFormula deployed at:", address(tokenBoilerPlate));
    }
}
