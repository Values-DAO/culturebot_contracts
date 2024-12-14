// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CultureBotTokenBoilerPlate} from "src/ExponentialBC/CultureTokenBoilerPlate.sol";
import {AggregatorV3Interface} from "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract CultureBotFactory {
    //error
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

    address[] public memeTokenAddresses;

    mapping(address => CommunityTokenDeets) public addressToMemeTokenMapping;

    AggregatorV3Interface v3Interface;

    uint constant DECIMALS = 10 ** 18;
    uint constant MEMECOIN_GRADUATION_MC = 69420;
    uint constant ETH_AMOUNT_TO_GRADUATE = 24 ether;
    uint constant MAX_SUPPLY = 100000000000 * DECIMALS;
    uint constant INIT_SUPPLY = (10 * MAX_SUPPLY) / 100;

    uint128 public constant PRICE_PRECISION = 1e6;
    uint256 public constant INITIAL_PRICE_USD = 10000000000000; // Initial price in USD (P0),  10^13 => $0.00001 //
    uint256 public constant K = 8 * 10 ** 15; // Growth rate (k), scaled to avoid precision loss (0.01 * 10^18)

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
    ) public payable returns (address) {
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
        address memeTokenAddress = address(ct);
        CommunityTokenDeets memory newlyCreatedToken = CommunityTokenDeets(
            name,
            symbol,
            description,
            0,
            memeTokenAddress,
            msg.sender
        );
        memeTokenAddresses.push(memeTokenAddress);
        addressToMemeTokenMapping[memeTokenAddress] = newlyCreatedToken;
        return memeTokenAddress;
    }

    function getAllMemeTokens()
        public
        view
        returns (CommunityTokenDeets[] memory)
    {
        CommunityTokenDeets[] memory allTokens = new CommunityTokenDeets[](
            memeTokenAddresses.length
        );
        for (uint i = 0; i < memeTokenAddresses.length; i++) {
            allTokens[i] = addressToMemeTokenMapping[memeTokenAddresses[i]];
        }
        return allTokens;
    }

    function buyMemeToken(
        address memeTokenAddress,
        uint tokenQty
    ) public payable returns (uint) {
        //check if memecoin is listed
        CommunityTokenDeets storage listedToken = addressToMemeTokenMapping[
            memeTokenAddress
        ];

        CultureBotTokenBoilerPlate memeTokenCt = CultureBotTokenBoilerPlate(
            memeTokenAddress
        );
        if (
            addressToMemeTokenMapping[memeTokenAddress].tokenAddress ==
            address(0)
        ) revert CBP__InvalidTokenAddress();

        // check to ensure funding goal is not met
        if (
            // calculateGraduationEthValueInUsd() >
            listedToken.fundingRaised >= ETH_AMOUNT_TO_GRADUATE
        ) revert CBP__BondingCurveAlreadyGraduated();

        uint currentSupply = memeTokenCt.totalSupply();
        uint available_qty = MAX_SUPPLY - currentSupply;

        uint scaled_available_qty = available_qty / DECIMALS;
        uint tokenQty_scaled = tokenQty * DECIMALS;

        require(
            tokenQty <= scaled_available_qty,
            "Not enough available supply"
        );

        // calculate the cost for purchasing tokenQty tokens as per the exponential bonding curve formula
        uint currentSupplyScaled = (currentSupply - INIT_SUPPLY) / DECIMALS;
        uint requiredEth = calculateCost(currentSupplyScaled, tokenQty);

        // check if user has sent correct value of eth to facilitate this purchase
        require(msg.value >= requiredEth, "Incorrect value of ETH sent");

        // Incerement the funding
        listedToken.fundingRaised += msg.value;

        // mint the tokens
        memeTokenCt.tokenMint(msg.sender, tokenQty_scaled);

        return 1;
    }

    // Function to calculate the cost in wei for purchasing `tokensToBuy` starting from `currentSupply`
    function calculateCost(
        uint256 currentSupply,
        uint256 tokensToBuy
    ) public view returns (uint256) {
        uint256 initialPrice = calculateInitialPrice(INITIAL_PRICE_USD);
        // Calculate the exponent parts scaled to avoid precision loss
        uint256 exponent1 = (K * (currentSupply + tokensToBuy)) / 10 ** 18;
        uint256 exponent2 = (K * currentSupply) / 10 ** 18;

        // Calculate e^(kx) using the exp function
        uint256 exp1 = exp(exponent1);
        uint256 exp2 = exp(exponent2);

        // Cost formula: (P0 / k) * (e^(k * (currentSupply + tokensToBuy)) - e^(k * currentSupply))
        // We use (P0 * 10^18) / k to keep the division safe from zero
        uint256 cost = (initialPrice * 10 ** 18 * (exp1 - exp2)) / K; // Adjust for k scaling without dividing by zero
        return cost;
    }

    // Improved helper function to calculate e^x for larger x using a Taylor series approximation
    function exp(uint256 x) internal pure returns (uint256) {
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
