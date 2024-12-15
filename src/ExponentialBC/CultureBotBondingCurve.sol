//SPDX-License-Identifier:MIT

pragma solidity 0.8.24;

import {CultureBotTokenBoilerPlate} from "src/ExponentialBC/CultureTokenBoilerPlate.sol";
import {AggregatorV3Interface} from "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract CultureBotBondingCurve {
    error CBP__InvalidTokenAddress();
    error CBP__BondingCurveAlreadyGraduated();

    struct CommunityTokenDeets {
        string name;
        string symbol;
        string description;
        uint fundingRaised;
        address tokenAddress;
        address creatorAddress;
    }

    mapping(address => CommunityTokenDeets) public addressToTokenMapping;

    AggregatorV3Interface v3Interface;

    uint256 public activeSupply;

    uint constant DECIMALS = 10 ** 18;
    uint constant MEMECOIN_GRADUATION_MC = 69420;
    uint constant ETH_AMOUNT_TO_GRADUATE = 24 ether;
    uint constant MAX_SUPPLY = 100000000000 * DECIMALS;
    uint constant INIT_SUPPLY = (10 * MAX_SUPPLY) / 100;

    uint128 public constant PRICE_PRECISION = 1e6;
    uint256 public constant INITIAL_PRICE_USD = 10000000000000; // Initial price in USD (P0),  10^13 => $0.00001 //
    uint256 public constant INITIAL_PRICE_IN_ETH = 0.00000003 ether;
    uint256 public constant K = 8 * 10 ** 18; // Growth rate (k), scaled to avoid precision loss (0.01 * 10^18)

    event BondinCurveInitialised(
        address curveAddress,
        address tokenAddress,
        string tokenName,
        string tokenTicker
    );

    constructor(
        string memory name,
        string memory symbol,
        string memory description,
        uint fundingRaised,
        address tokenAddress,
        address creatorAddress
    ) {
        addressToTokenMapping[tokenAddress] = CommunityTokenDeets(
            name,
            symbol,
            description,
            fundingRaised,
            tokenAddress,
            creatorAddress
        );
        emit BondinCurveInitialised(address(this), tokenAddress, name, symbol);
    }

    function buyToken(
        address tokenAddress,
        uint tokenQty
    ) public payable returns (uint) {
        //check if memecoin is listed
        CommunityTokenDeets storage listedToken = addressToTokenMapping[
            tokenAddress
        ];

        CultureBotTokenBoilerPlate memeTokenCt = CultureBotTokenBoilerPlate(
            tokenAddress
        );

        if (listedToken.tokenAddress == address(0))
            revert CBP__InvalidTokenAddress();

        // check to ensure funding goal is not met
        if (
            // calculateGraduationEthValueInUsd() >
            listedToken.fundingRaised >= ETH_AMOUNT_TO_GRADUATE
        ) revert CBP__BondingCurveAlreadyGraduated();

        // uint currentSupply = memeTokenCt.totalSupply();

        uint available_qty = MAX_SUPPLY - INIT_SUPPLY;

        uint scaled_available_qty = available_qty / DECIMALS;

        uint tokenQty_scaled = tokenQty;

        require(
            tokenQty <= scaled_available_qty,
            "Not enough available supply"
        );

        // calculate the cost for purchasing tokenQty tokens as per the exponential bonding curve formula
        // uint currentSupplyScaled = (currentSupply - INIT_SUPPLY) / DECIMALS;
        uint requiredEth = calculateCost(activeSupply, tokenQty);

        // check if user has sent correct value of eth to facilitate this purchase
        require(msg.value >= requiredEth, "Incorrect value of ETH sent");

        // Incerement the funding
        listedToken.fundingRaised += msg.value;
        activeSupply += tokenQty;

        // mint the tokens
        memeTokenCt.transfer(msg.sender, tokenQty_scaled);

        return 1;
    }

    // Function to calculate the cost in wei for purchasing `tokensToBuy` starting from `currentSupply`
    function calculateCost(
        uint256 _activeSupply,
        uint256 tokensToBuy
    ) public pure returns (uint256) {
        // Calculate the exponent parts scaled to avoid precision loss
        uint256 exponent1 = (K * (_activeSupply + tokensToBuy)) / 10 ** 18;

        uint256 exponent2 = (K * _activeSupply) / 10 ** 18;

        // Calculate e^(kx) using the exp function
        uint256 exp1 = exponent(exponent1);

        uint256 _exp2 = exponent(exponent2);

        // Cost formula: (P0 / k) * (e^(k * (currentSupply + tokensToBuy)) - e^(k * currentSupply))
        // We use (P0 * 10^18) / k to keep the division safe from zero
        uint256 cost = (INITIAL_PRICE_IN_ETH * 10 ** 18 * (exp1 - _exp2)) / K; // Adjust for k scaling without dividing by zero
        return cost;
    }

    // Improved helper function to calculate e^x for larger x using a Taylor series approximation
    function exponent(uint256 x) public pure returns (uint256) {
        uint256 sum = 10 ** 18; // Start with 1 * 10^18 for precision
        uint256 term = 10 ** 18; // Initial term = 1 * 10^18
        uint256 xPower = x; // Initial power of x

        for (uint256 i = 1; i <= 20; i++) {
            // Increase iterations for better accuracy
            term = (term * xPower) / (i * 10 ** 18); // x^i / i!
            sum += term;

            // Prevent overflow and unnecessary calculations
            if (term < 1) break;
        }

        return sum;
    }

    function calculateInitialPrice(
        uint256 initialPriceUsd
    ) internal view returns (uint256 initialPriceInEth) {
        (, int256 ethPrice, , , ) = v3Interface.latestRoundData();
        initialPriceInEth =
            (uint256(ethPrice) * PRICE_PRECISION) /
            initialPriceUsd;
    }

    function calculateGraduationEthValueInUsd(
        uint256 currentBCEthAmount
    ) internal view returns (uint256 currentBCEthValue) {
        (, int256 ethPrice, , , ) = v3Interface.latestRoundData();

        currentBCEthValue =
            (uint256(ethPrice) * currentBCEthAmount) /
            PRICE_PRECISION;
    }
}
