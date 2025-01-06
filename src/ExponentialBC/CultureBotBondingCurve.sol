//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {CultureBotTokenBoilerPlate} from "src/ExponentialBC/CultureTokenBoilerPlate.sol";
import {INonfungiblePositionManager, IUniswapV3Factory, IWETH9} from "./interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TickMath} from "v3-core/contracts/libraries/TickMath.sol";
import {UD60x18, ud, exp} from "prb-math/UD60x18.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/// @title CultureBot Bonding Curve
/// @notice Implements an exponential bonding curve with Uniswap V3 liquidity provision and this is not a complete implementation
/// @dev Uses PRBMath for precise mathematical calculations and Chainlink for price feeds
contract CultureBotBondingCurve is Ownable, IERC721Receiver {
    using TickMath for int24;

    /// @notice Custom errors for better gas efficiency
    error CBP__InvalidLogAmount();
    error CBP__IncorrectCostValue();
    error CBP__InvalidTokenAddress();
    error CBP__SupplyCapExceededAlready();
    error CBP__InsufficientAvailableSupply();
    error CBP__BondingCurveAlreadyGraduated();

    /// @notice Struct containing community coin details
    /// @dev Packed for optimal storage
    struct CommunityCoinDeets {
        string name;
        string symbol;
        bool isGraduated;
        string description;
        address tokenAddress;
        address creatorAddress;
        uint256 fundingRaised;
    }

    /// @notice Chainlink price feed interface
    AggregatorV3Interface public immutable v3Interface;
    CommunityCoinDeets public communityCoinDeets;

    /// @notice Current active supply of tokens
    uint256 public activeSupply;

    /// @notice Constants used throughout the contract
    /// @dev All constants are immutable and most are private for gas optimization
    address private constant BASE_ETH_PRICEFEED =
        0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1;
    uint256 private constant DECIMALS = 1e18;
    uint256 private constant ETH_AMOUNT_TO_GRADUATE = 24 ether;
    uint256 public constant BONDINGCURVE_TOTAL_SUPPLY =
        54_000_000_000 * DECIMALS;
    uint256 public constant LP_SUPPLY = 13_500_000_000;
    uint128 private constant PRICE_PRECISION = 1e8;
    uint256 private constant INITIAL_PRICE_IN_ETH = 0.000000000024269 ether;
    uint256 private constant K = 69420 * DECIMALS;

    /// @notice Events for better transparency and off-chain tracking
    event TokensPurchased(
        address indexed buyer,
        address indexed token,
        uint256 amount,
        uint256 cost,
        uint256 currentTokenPrice,
        uint256 currentTokenSupply
    );
    event PoolConfigured(
        address indexed token,
        address indexed weth,
        uint256 positionId
    );

    constructor(
        string memory name,
        string memory symbol,
        string memory description,
        uint96 fundingRaised,
        address tokenAddress,
        address creatorAddress
    ) Ownable(msg.sender) {
        communityCoinDeets = CommunityCoinDeets({
            name: name,
            symbol: symbol,
            isGraduated: false,
            description: description,
            tokenAddress: tokenAddress,
            creatorAddress: creatorAddress,
            fundingRaised: fundingRaised
        });
        v3Interface = AggregatorV3Interface(BASE_ETH_PRICEFEED);
    }

    /// @notice Purchase tokens using the bonding curve
    /// @param usdAmount USD amount to spend
    /// @return success Returns 1 if successful
    function buyToken(uint32 usdAmount) public payable returns (uint256) {
        CommunityCoinDeets storage listedToken = communityCoinDeets;

        if (listedToken.tokenAddress == address(0))
            revert CBP__InvalidTokenAddress();
        if (activeSupply >= BONDINGCURVE_TOTAL_SUPPLY)
            revert CBP__SupplyCapExceededAlready();
        if (listedToken.fundingRaised >= ETH_AMOUNT_TO_GRADUATE)
            revert CBP__BondingCurveAlreadyGraduated();

        uint256 tokenQty = calculateCoinAmountOnUSDAmt(usdAmount);

        uint256 requiredEth = calculateCost(tokenQty);

        if (msg.value < requiredEth) revert CBP__IncorrectCostValue();

        uint256 available_qty = (BONDINGCURVE_TOTAL_SUPPLY - activeSupply) /
            DECIMALS;
        if (tokenQty > available_qty) revert CBP__InsufficientAvailableSupply();

        uint256 tokenQty_scaled = tokenQty * DECIMALS;

        listedToken.fundingRaised += requiredEth;
        activeSupply += tokenQty_scaled;

        CultureBotTokenBoilerPlate(listedToken.tokenAddress).transfer(
            msg.sender,
            tokenQty_scaled
        );

        emit TokensPurchased(
            msg.sender,
            listedToken.tokenAddress,
            tokenQty_scaled,
            requiredEth,
            calculateCost(1),
            activeSupply
        );
        return 1;
    }

    /// @notice Configure Uniswap V3 pool for the token
    /// @dev Sets up initial liquidity position
    function configurePool(
        uint24 fee,
        int24 tick,
        address newToken,
        address wethAddress,
        int24 tickSpacing,
        address _positionManager,
        address poolfactory
    ) external onlyOwner returns (uint256 positionId) {
        CommunityCoinDeets storage listedToken = communityCoinDeets;
        (address token0, address token1) = newToken < wethAddress
            ? (newToken, wethAddress)
            : (wethAddress, newToken);

        // Determine correct amounts based on token order
        (uint256 amount0Desired, uint256 amount1Desired) = newToken <
            wethAddress
            ? (LP_SUPPLY * DECIMALS, listedToken.fundingRaised)
            : (listedToken.fundingRaised, LP_SUPPLY * DECIMALS);

        IUniswapV3Factory uniswapV3Factory = IUniswapV3Factory(poolfactory);
        INonfungiblePositionManager positionManager = INonfungiblePositionManager(
                _positionManager
            );

        IWETH9(wethAddress).deposit{value: listedToken.fundingRaised}();

        uint160 sqrtPriceX96 = tick.getSqrtRatioAtTick();
        address pool = uniswapV3Factory.createPool(newToken, wethAddress, fee);
        IUniswapV3Factory(pool).initialize(sqrtPriceX96);

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: tick,
                tickUpper: maxUsableTick(tickSpacing),
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            });

        // Create position
        (positionId, , , ) = positionManager.mint(params);

        emit PoolConfigured(newToken, wethAddress, positionId);
    }

    // Cost formula: (P0 / k) * (e^(k * (activeSupply + tokensToBuy)) - e^(k * activeSupply))
    /// @notice Calculate cost of tokens based on bonding curve
    /// @param tokensToBuy Amount of tokens to purchase
    /// @return Cost in ETH
    function calculateCost(uint256 tokensToBuy) public view returns (uint256) {
        UD60x18 p0 = ud(INITIAL_PRICE_IN_ETH * DECIMALS);
        UD60x18 kud = ud(K);
        UD60x18 dynamicScaleFactor = calculateDynamicScaleFactor(
            activeSupply / DECIMALS
        );

        UD60x18 s = ud(activeSupply / DECIMALS);
        UD60x18 t = ud(tokensToBuy);

        UD60x18 term1 = exp(kud.mul(s.add(t)));
        UD60x18 term2 = exp(kud.mul(s));

        UD60x18 cost = p0.div(kud).mul(term1.sub(term2));

        return ((cost).unwrap() * (dynamicScaleFactor.unwrap() + 1));
    }

    /// @notice Calculate dynamic scale factor based on supply
    /// @param _activeSupply Current active supply
    /// @return Scale factor as UD60x18
    function calculateDynamicScaleFactor(
        uint256 _activeSupply
    ) internal pure returns (UD60x18) {
        // Logarithmic Scaling with Supply Proximity
        UD60x18 supplyRatio = ud(
            (_activeSupply * 1e18) / (BONDINGCURVE_TOTAL_SUPPLY / DECIMALS)
        );

        // Multi-Phase Scaling Logic
        UD60x18 logComponent = ud(log2(_activeSupply == 0 ? 1 : _activeSupply));
        UD60x18 proximityFactor = supplyRatio.pow(ud(5e17)); // Square root-like progression

        // Combine Scaling Components
        return logComponent.mul(proximityFactor);
    }

    /// @notice Calculate the amount of ETH equivalent for a given token purchase amount in USD
    /// @param usdAmount Amount in USD
    /// @return requiredEth Amount of ETH required
    function calculateRequiredEthForUsd(
        uint32 usdAmount
    ) public view returns (uint256 requiredEth) {
        if (usdAmount == 0) return 0;
        uint256 tokenQty = calculateCoinAmountOnUSDAmt(usdAmount);

        requiredEth = calculateCost(tokenQty);
    }

    /// @notice Calculate the coin amount that can be purchased with a given USD amount
    /// @param purchaseAmountInUsd Amount in USD
    /// @return Amount of coins that can be purchased
    /// @dev Uses Chainlink price feed for ETH/USD conversion
    function calculateCoinAmountOnUSDAmt(
        uint32 purchaseAmountInUsd
    ) public view returns (uint256) {
        uint256 costInEthPerCoin = calculateCost(1);

        (, int256 ethPrice, , , ) = v3Interface.latestRoundData();

        uint256 costInUsdPerCoin = costInEthPerCoin *
            (uint256(ethPrice) / PRICE_PRECISION);

        return ((purchaseAmountInUsd * DECIMALS) / costInUsdPerCoin);
    }

    /// @notice Calculate the maximum usable tick for Uniswap V3 pool
    /// @param tickSpacing The tick spacing of the pool
    /// @return The maximum tick that can be used
    /// @dev Ensures tick is aligned with spacing
    function maxUsableTick(int24 tickSpacing) internal pure returns (int24) {
        unchecked {
            return (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
        }
    }

    /// @notice Handle the receipt of an NFT
    /// @dev The ERC721 smart contract calls this function on the recipient
    ///      after a `transfer`. This function MAY throw to revert and reject the
    ///      transfer. Return of other than the magic value MUST result in the
    ///      transaction being reverted.
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /// @notice Calculate the base-2 logarithm of a number using bit manipulation
    /// @param x The number to calculate the logarithm of
    /// @return y The base-2 logarithm of x
    /// @dev Uses De Bruijn sequence for efficient calculation
    function log2(uint256 x) internal pure returns (uint256) {
        if (x <= 0) revert CBP__InvalidLogAmount();
        uint256 y;
        assembly {
            let temp := x
            temp := sub(temp, 1)
            temp := or(temp, div(temp, 2))
            temp := or(temp, div(temp, 4))
            temp := or(temp, div(temp, 8))
            temp := or(temp, div(temp, 16))
            temp := or(temp, div(temp, 32))
            temp := or(temp, div(temp, 64))
            temp := or(temp, div(temp, 128))
            temp := or(temp, div(temp, 256))

            // base-2 logarithm via De Bruijn sequence
            y := mul(gt(temp, 0xFFFFFFFF), 32)
            y := or(y, mul(gt(shr(y, temp), 0xFFFF), 16))
            y := or(y, mul(gt(shr(y, temp), 0xFF), 8))
            y := or(y, mul(gt(shr(y, temp), 0xF), 4))
            y := or(y, mul(gt(shr(y, temp), 0x3), 2))
            y := or(y, mul(gt(shr(y, temp), 0x1), 1))
        }
        return y;
    }

    /// @notice Get the current price of the token in ETH
    /// @return Current price according to the bonding curve
    function getCurrentPrice() external view returns (uint256) {
        return calculateCost(1);
    }
}
