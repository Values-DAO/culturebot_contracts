// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/ExponentialBC/CBRewardDistributionModule.sol";

contract DeployCBRewardDistributionModule is Script {
    address public safe = 0x57cb6f115BC64187Bf8c77681dD89768F8863c5b;

    function run() external {
        vm.startBroadcast();

        // Deploy the CBRewardDistributionModule contract
        CBRewardDistributionModule rewardDistributionModule = new CBRewardDistributionModule(
                safe
            );

        // Log the address of the deployed contract
        console.log(
            "CBRewardDistributionModule deployed at:",
            address(rewardDistributionModule)
        );

        vm.stopBroadcast();
    }
}
