// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CultureBotTokenBoilerPlate} from "src/ExponentialBC/CultureTokenBoilerPlate.sol";
import {AggregatorV3Interface} from "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {CultureBotBondingCurve} from "./CultureBotBondingCurve.sol";

contract CultureBotFactory {
    AggregatorV3Interface v3Interface;

    uint constant DECIMALS = 10 ** 18;
    uint constant MAX_SUPPLY = 100000000000 * DECIMALS;
    uint constant INIT_SUPPLY = (10 * MAX_SUPPLY) / 100;
    uint constant BONDINGCURVE_SUPPLY = (MAX_SUPPLY * 90) / 100;

    event TokenCreated(
        address deployer,
        string name,
        string symbol,
        address tokenAddress
    );

    constructor(AggregatorV3Interface _v3Interface) {
        v3Interface = AggregatorV3Interface(_v3Interface);
    }

    function initialiseToken(
        string memory name,
        string memory symbol,
        string memory description,
        address[] memory allocationAddys,
        uint256[] memory allocationAmount
    ) public payable returns (address, address) {
        //should deploy the meme token, mint the initial supply to the token factory contract
        CultureBotTokenBoilerPlate ct = new CultureBotTokenBoilerPlate(
            name,
            symbol,
            MAX_SUPPLY,
            allocationAddys,
            allocationAmount,
            address(this)
        );
        emit TokenCreated(msg.sender, name, symbol, address(ct));
        CultureBotBondingCurve newBondingCurve = new CultureBotBondingCurve(
            name,
            symbol,
            description,
            0,
            address(ct),
            msg.sender
        );
        // In factory or token initialization
        ct.approve(address(newBondingCurve), BONDINGCURVE_SUPPLY);
        ct.tokenMint(address(newBondingCurve), BONDINGCURVE_SUPPLY);

        return (address(ct), address(newBondingCurve));
    }
}
