//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CultureBotReward is Ownable {
    error CBR__InvalidParams();

    constructor() Ownable(msg.sender) {}

    function disrtibuteRewards(
        address tokenAddy,
        address[] memory allocationAddress,
        uint256[] memory allocationAmount
    ) public onlyOwner {
        if (allocationAddress.length != allocationAmount.length)
            revert CBR__InvalidParams();

        for (uint i = 0; i < allocationAddress.length; i++) {
            IERC20(tokenAddy).transfer(
                allocationAddress[i],
                allocationAmount[i]
            );
        }
    }

    function checkRewardTokenBalance(
        address _token
    ) public view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }
}
