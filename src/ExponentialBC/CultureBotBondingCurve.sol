//SPDX-License-Identifier:MIT

pragma solidity 0.8.24;

import {CultureBotTokenBoilerPlate} from "src/ExponentialBC/CultureTokenBoilerPlate.sol";
import {AggregatorV3Interface} from "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {UD60x18, ud, ln, exp} from "prb-math/UD60x18.sol";

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

    // Cost formula: (P0 / k) * (e^(k * (activeSupply + tokensToBuy)) - e^(k * activeSupply))
    function calculateCost(
        uint256 _activeSupply,
        uint256 tokensToBuy
    ) public pure returns (uint256) {
        UD60x18 p0 = ud(INITIAL_PRICE_IN_ETH * DECIMALS);

        UD60x18 s = ud(_activeSupply);
        UD60x18 t = ud(tokensToBuy);
        UD60x18 kud = ud(K);

        UD60x18 term1 = exp(kud.mul(s.add(t)));

        UD60x18 term2 = exp(kud.mul(s));

        UD60x18 cost = p0.div(kud).mul(term1.sub(term2));

        return (cost.unwrap());
    }

    //y= (1/k)*ln( (k⋅cost/P0*e^kx)+1)
    function calculateTokensForEth(
        uint256 _activeSupply,
        uint256 ethAmount
    ) public pure returns (uint256 tokenQuantity) {
        // Convert inputs to UD60x18
        UD60x18 cost = ud(ethAmount);
        UD60x18 p0 = ud(INITIAL_PRICE_IN_ETH);
        UD60x18 kud = ud(K);
        UD60x18 xud = ud(_activeSupply);

        // Calculate e^(kx)
        UD60x18 expKx = exp(kud.mul(xud));

        // Calculate the numerator: k * cost
        UD60x18 numerator = kud.mul(cost);

        // Calculate the denominator: P0 * e^(kx)
        UD60x18 denominator = p0.mul(expKx);

        // Calculate the argument of the natural log: (numerator / denominator) + 1
        UD60x18 lnArgument = numerator.div(denominator).add(ud(1 ether));

        // Calculate y using the formula: y = (1 / k) * ln(lnArgument)
        UD60x18 y = ln(lnArgument).div(kud);

        return y.unwrap();
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
