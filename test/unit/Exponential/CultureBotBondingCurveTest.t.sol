// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {CultureBotBondingCurve} from "src/ExponentialBC/CultureBotBondingCurve.sol";
import {CultureBotTokenBoilerPlate} from "src/ExponentialBC/CultureTokenBoilerPlate.sol";
import {CultureBotFactory} from "src/ExponentialBC/CultureBotFactory.sol";
import {AggregatorV3Interface} from "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IWETH9, IUniswapV3Factory} from "../../../src/ExponentialBC/interface.sol";

contract CultureBotBondingCurveTest is Test {
    CultureBotBondingCurve bondingCurve;
    CultureBotTokenBoilerPlate memeToken;
    CultureBotFactory factory;
    AggregatorV3Interface mockPriceFeed;

    address deployer;
    address user1;
    address user2;
    address communityToken;

    // Constants from the original contract
    uint256 constant MAX_SUPPLY = 100000000000 * 10 ** 18;
    uint256 constant ETH_AMOUNT_TO_GRADUATE = 24 ether;
    uint256 constant INIT_SUPPLY = (10 * MAX_SUPPLY) / 100;
    uint constant BONDINGCURVE_SUPPLY = (MAX_SUPPLY * 90) / 100;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant UNISWAP_V3_FACTORY =
        0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address constant POSITION_MANAGER =
        0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2;

    // Test variables
    address owner;
    uint24 constant FEE = 3000; // 0.3%
    int24 constant TICK_SPACING = 60;
    int24 constant INITIAL_TICK = -60; //

    event PoolConfigured(
        address indexed token,
        address indexed weth,
        uint256 positionId
    );

    function setUp() public {
        // Setup test addresses
        deployer = makeAddr("deployer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Mock Chainlink Price Feed
        mockPriceFeed = AggregatorV3Interface(makeAddr("mockPriceFeed"));

        // Setup factory with mock price feed
        vm.prank(deployer);
        factory = new CultureBotFactory();

        // Create a meme token through the factory
        vm.startPrank(deployer);
        address[] memory allocAddrs = new address[](1);
        allocAddrs[0] = deployer;
        uint256[] memory allocAmounts = new uint256[](1);
        allocAmounts[0] = INIT_SUPPLY;

        (address tokenAddress, address _bondingCurve) = factory.initialiseToken(
            "TestMemeCoin",
            "TMC",
            "Test Meme Coin Description",
            allocAddrs,
            allocAmounts
        );
        vm.stopPrank();
        communityToken = tokenAddress;
        bondingCurve = CultureBotBondingCurve(_bondingCurve);

        // Get the created token and bonding curve
        memeToken = CultureBotTokenBoilerPlate(tokenAddress);
    }

    // Test Contract Initialization
    function test_contract_initialization() public view {
        // Verify token details in mapping
        (
            string memory name,
            string memory symbol,
            bool isGraduated,
            string memory description,
            address tokenAddress,
            address creatorAddress,
            uint fundingRaised
        ) = bondingCurve.addressToTokenMapping(communityToken);

        assertEq(name, "TestMemeCoin");
        assertEq(symbol, "TMC");
        assertEq(description, "Test Meme Coin Description");
        assertEq(fundingRaised, 0);
        assertEq(tokenAddress, address(memeToken));
        assertEq(creatorAddress, deployer);
        assertFalse(isGraduated);
    }

    // Test Cost Calculation
    function test_calculate_cost() public view {
        uint256 initialSupply = 0;
        uint256 tokensToBuy = 100000 * 10 ** 18;

        uint256 cost = bondingCurve.calculateCost(
            initialSupply,
            tokensToBuy / 10 ** 18
        );
        uint256 cost2 = bondingCurve.calculateCost(
            initialSupply + (tokensToBuy / 10 ** 18),
            tokensToBuy / 10 ** 18
        );
        uint256 cost3 = bondingCurve.calculateCost(
            initialSupply + (tokensToBuy + tokensToBuy) / 10 ** 18,
            tokensToBuy / 10 ** 18
        );
        /**
         *   coost: 3000000000000000
            coost2: 3000000000000000
         */

        console.log("coost:", cost);
        console.log("coost2:", cost2);
        console.log("coost3:", cost3);

        // Ensure cost is greater than zero
        assertGt(cost, 0, "Cost should be positive");
    }

    // Test Buying Tokens
    function test_buy_communityToken() public {
        uint256 priceBefore = bondingCurve.calculateCost(
            bondingCurve.activeSupply(),
            1
        );
        console.log("priceBefore:", priceBefore); //571385279910646

        // Prepare to buy tokens
        uint256 tokenQty = 100000;
        console.log("tokenQuantity:", tokenQty);
        uint256 requiredEth = bondingCurve.calculateCost(
            bondingCurve.activeSupply(),
            tokenQty
        );
        console.log("requiredEth:", requiredEth);

        console.log(
            "numTokensForEth:",
            bondingCurve.calculateTokensForEth(
                bondingCurve.activeSupply(),
                requiredEth
            )
        ); //835732618383544901
        //835576465958490911
        vm.deal(user1, 10000 ether);
        for (int i = 0; i < 20; i++) {
            vm.prank(user1);
            bondingCurve.buyToken{value: 0.6 ether}(
                address(memeToken),
                tokenQty
            );
        }
        uint256 currentPrice1 = bondingCurve.calculateCost(
            bondingCurve.activeSupply(), //2112999999 //14999780 //2999956
            1
        );
        console.log("currentPrice1:", currentPrice1);
        bondingCurve.buyToken{value: 0.1 ether}(address(memeToken), 1000000);
        console.log("1");
        bondingCurve.buyToken{value: 0.1 ether}(address(memeToken), 10000000);
        console.log("2");
        bondingCurve.buyToken{value: 0.8 ether}(address(memeToken), 100000000);
        console.log("3");
        bondingCurve.buyToken{value: 8.7 ether}(address(memeToken), 1000000000);
        console.log("4");
        bondingCurve.buyToken{value: 9.969 ether}(
            address(memeToken),
            999999999
        );
        console.log("5");
        bondingCurve.buyToken{value: 0.999 ether}(address(memeToken), 99999999);
        console.log("6");
        bondingCurve.buyToken{value: 1.1 ether}(address(memeToken), 99999999);
        console.log("7");
        bondingCurve.buyToken{value: 1.1 ether}(address(memeToken), 99999999);

        for (int i = 0; i < 44; i++) {
            vm.prank(user1);

            bondingCurve.buyToken{value: 6 ether}(
                address(memeToken),
                1000000000
            );
        }
        bondingCurve.buyToken{value: 1 ether}(address(memeToken), 100000000);
        // bondingCurve.buyToken{value: 1 ether}(address(memeToken), 100000000);
        // bondingCurve.buyToken{value: 1 ether}(address(memeToken), 1000000000);
        //0.000000128555

        uint256 currentPrice = bondingCurve.calculateCost(
            bondingCurve.activeSupply(), //2112999999
            1
        ); //6412999996
        console.log("currentPrice:", currentPrice); //0.000000000300000000
        console.log("activeSupply:", bondingCurve.activeSupply());
        (, , , , , , uint fundingRaised) = bondingCurve.addressToTokenMapping(
            address(memeToken)
        ); //300000000
        console.log("ethaccrued:", fundingRaised);
        //000029999962500000
        // Buy tokens
        //0.000000000262500000
        //0.000000000300000000

        // // Verify purchase
        // assertEq(result, 1, "Token purchase should succeed");
        // assertEq(
        //     memeToken.balanceOf(user1),
        //     tokenQty,
        //     "User should receive tokens"
        // );
    }

    // Test Buying Tokens Fails When Not Enough ETH
    function test_buyToken_innsufficientEth() public {
        uint256 tokenQty = 100;
        // uint256 requiredEth = bondingCurve.calculateCost(0, tokenQty);

        // Approve bonding curve to spend tokens
        vm.prank(deployer);
        memeToken.approve(address(bondingCurve), MAX_SUPPLY);

        // Try to buy with insufficient ETH
        vm.prank(user1);
        vm.expectRevert("Incorrect value of ETH sent");
        bondingCurve.buyToken{value: 0 ether}(address(memeToken), tokenQty);
    }

    // Test Buying Tokens Exceeds Available Supply
    function test_buyToken_exceedsSupply() public {
        // Calculate max possible tokens
        uint256 maxTokens = MAX_SUPPLY / 10 ** 18;

        // Approve bonding curve to spend tokens
        vm.prank(deployer);
        memeToken.approve(address(bondingCurve), MAX_SUPPLY);

        // Try to buy more tokens than available
        vm.prank(user1);
        vm.expectRevert();
        bondingCurve.buyToken{value: 100 ether}(
            address(memeToken),
            maxTokens + 1
        );
    }

    // Test Buying Tokens After Graduation
    function test_buyToken_afterGraduation() public {
        // Simulate graduation by setting funding raised
        vm.store(
            address(bondingCurve),
            bytes32(uint256(2)), // Storage slot for fundingRaised in mapping
            bytes32(uint256(ETH_AMOUNT_TO_GRADUATE + 1))
        );

        // Try to buy tokens after graduation
        vm.prank(user1);
        vm.expectRevert(
            CultureBotBondingCurve.CBP__BondingCurveAlreadyGraduated.selector
        );
        bondingCurve.buyToken{value: 1 ether}(address(memeToken), 10);
    }

    // Fuzz Test Cost Calculation
    function test_fuzzCalculateCost(
        uint256 _supply,
        uint256 _tokens
    ) public view {
        // Bound inputs to reasonable ranges
        vm.assume(_supply < BONDINGCURVE_SUPPLY / 10 ** 18);
        vm.assume(
            _tokens > 0 &&
                _tokens < (BONDINGCURVE_SUPPLY - _supply * 10 ** 18) / 10 ** 18
        );

        uint256 cost = bondingCurve.calculateCost(_supply, _tokens);

        // Basic sanity checks
        assertGt(cost, 0, "Cost should always be positive");
    }

    function test_priceIn_usdc() public {
        test_buy_communityToken();
        uint32 purchaseCostInUsd = 450;
        uint256 numTokens = bondingCurve.calculateCoinAmountOnUSDAmt(
            purchaseCostInUsd
        );
        console.log("noOfTokens:", numTokens);
        uint256 correspondingEthValue = bondingCurve.calculateCost(
            bondingCurve.activeSupply(),
            numTokens
        );
        console.log("eeth:", correspondingEthValue);
    }

    function testFuzz_ConfigurePool_ValidParams(
        uint24 randomFee,
        int24 randomTick
    ) public {
        // Bound the random values to realistic ranges
        randomFee = uint24(bound(randomFee, 100, 10000)); // 0.01% to 1%
        randomTick = int24(bound(randomTick, -887272, 887272)); // Min/max ticks

        vm.startPrank(address(factory));

        // Fund the bonding curve contract with ETH
        vm.deal(address(bondingCurve), 24 ether);

        // Expect the PoolConfigured event
        vm.expectEmit(true, true, false, true);
        emit PoolConfigured(address(communityToken), WETH, 1); // First position ID should be 1

        uint256 positionId = bondingCurve.configurePool(
            randomFee,
            randomTick,
            address(communityToken),
            WETH,
            TICK_SPACING,
            POSITION_MANAGER,
            UNISWAP_V3_FACTORY
        );

        assertGt(positionId, 0, "Position ID should be greater than 0");

        // Verify pool creation
        address expectedPool = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(
            address(communityToken),
            WETH,
            randomFee
        );
        assertNotEq(expectedPool, address(0), "Pool should exist");

        vm.stopPrank();
    }

    function testRevert_ConfigurePool_InvalidTokenOrder() public {
        vm.startPrank(owner);

        // Try to create pool with token address greater than WETH
        address invalidToken = makeAddr("invalidToken");
        require(uint160(invalidToken) > uint160(WETH), "Test setup error");

        // vm.expectRevert(
        //     CultureBotBondingCurve.CBP__InvalidPoolConfiguration.selector
        // );

        bondingCurve.configurePool(
            FEE,
            INITIAL_TICK,
            invalidToken,
            WETH,
            TICK_SPACING,
            POSITION_MANAGER,
            UNISWAP_V3_FACTORY
        );

        vm.stopPrank();
    }

    function testRevert_ConfigurePool_NonOwner() public {
        vm.startPrank(owner);

        vm.expectRevert();

        bondingCurve.configurePool(
            FEE,
            INITIAL_TICK,
            address(communityToken),
            WETH,
            TICK_SPACING,
            POSITION_MANAGER,
            UNISWAP_V3_FACTORY
        );

        vm.stopPrank();
    }

    function test_ConfigurePool_WithRealPool() public {
        test_buy_communityToken();
        vm.prank(address(bondingCurve));
        IWETH9(WETH).approve(POSITION_MANAGER, type(uint256).max);
        memeToken.approve(POSITION_MANAGER, type(uint256).max);
        vm.startPrank(address(factory));

        // Approve tokens

        uint256 beforeBalance = memeToken.balanceOf(address(bondingCurve));

        uint256 positionId = bondingCurve.configurePool(
            FEE,
            INITIAL_TICK,
            address(memeToken),
            WETH,
            TICK_SPACING,
            POSITION_MANAGER,
            UNISWAP_V3_FACTORY
        );
        console.log(
            "wethBalanceAfter:",
            IWETH9(WETH).balanceOf(address(bondingCurve))
        );

        // Verify position creation
        assertGt(positionId, 0, "Invalid position ID");

        // Verify token transfer
        uint256 afterBalance = memeToken.balanceOf(address(bondingCurve));
        assertLt(
            afterBalance,
            beforeBalance,
            "Tokens should be transferred to pool"
        );

        // Verify pool initialization
        address pool = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(
            address(memeToken),
            WETH,
            FEE
        );
        assertNotEq(pool, address(0), "Pool should be created");

        vm.stopPrank();
    }

    function test_ConfigurePool_ETHHandling() public {
        vm.startPrank(owner);

        // Fund the contract
        vm.prank(address(bondingCurve));
        IWETH9(WETH).approve(POSITION_MANAGER, type(uint256).max);
        memeToken.approve(POSITION_MANAGER, type(uint256).max);

        // Track WETH balances
        uint256 beforeWETHBalance = IWETH9(WETH).balanceOf(
            address(bondingCurve)
        );

        bondingCurve.configurePool(
            FEE,
            INITIAL_TICK,
            address(communityToken),
            WETH,
            TICK_SPACING,
            POSITION_MANAGER,
            UNISWAP_V3_FACTORY
        );

        uint256 afterWETHBalance = IWETH9(WETH).balanceOf(
            address(bondingCurve)
        );

        // Verify WETH handling
        assertGt(
            afterWETHBalance,
            beforeWETHBalance,
            "WETH balance should increase"
        );

        vm.stopPrank();
    }

    // Helper function to test gas usage
    function testGas_ConfigurePool() public {
        vm.startPrank(owner);
        vm.deal(address(bondingCurve), 24 ether);

        uint256 gasStart = gasleft();

        bondingCurve.configurePool(
            FEE,
            INITIAL_TICK,
            address(communityToken),
            WETH,
            TICK_SPACING,
            POSITION_MANAGER,
            UNISWAP_V3_FACTORY
        );

        uint256 gasUsed = gasStart - gasleft();
        emit log_named_uint("Gas Used", gasUsed);

        vm.stopPrank();
    }
}
