// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/ExponentialBC/CBRewardDistributionModule.sol";

contract DeployCBRewardDistributionModule is Script {
    address public safe = 0xD9d30b9cF4795cCF164A9bc4019268f0A0d12817;

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
