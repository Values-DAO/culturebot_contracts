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
    uint256 constant INIT_SUPPLY = (10 * MAX_SUPPLY) / (100 * 10 ** 18);
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
    int24 constant MAX_TICK = 600;

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
            deployer,
            allocAddrs,
            allocAmounts
        );
        vm.stopPrank();
        communityToken = tokenAddress;
        bondingCurve = CultureBotBondingCurve(_bondingCurve);

        // Get the created token and bonding curve
        memeToken = CultureBotTokenBoilerPlate(tokenAddress);
    }

    function test_launch_new_token() public {
        address[] memory allocAddrs = new address[](1);
        allocAddrs[0] = deployer;
        uint256[] memory allocAmounts = new uint256[](1);
        allocAmounts[0] = INIT_SUPPLY;

        factory.initialiseToken(
            "TestMemeCoin2",
            "TMC",
            "Test Meme Coin Description",
            deployer,
            allocAddrs,
            allocAmounts
        );
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
        ) = bondingCurve.communityCoinDeets();

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
        uint256 tokensToBuy = 100000 * 10 ** 18;

        uint256 cost = bondingCurve.calculateCost(tokensToBuy / 10 ** 18);
        uint256 cost2 = bondingCurve.calculateCost(tokensToBuy / 10 ** 18);
        uint256 cost3 = bondingCurve.calculateCost(tokensToBuy / 10 ** 18);
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

    function test_singleBuy() public {
        // Prepare to buy tokens
        uint32 purchaseCost = 1000;
        uint256 requiredEth = bondingCurve.calculateRequiredEthForUsd(
            purchaseCost
        );
        console.log("requiredEth:", requiredEth);

        // Buy tokens
        vm.deal(user1, 3 ether);
        vm.prank(user1);
        uint256 result = bondingCurve.buyToken{value: requiredEth}(
            purchaseCost
        );

        // Verify purchase
        assertEq(result, 1, "Token purchase should succeed");
    }

    // Test Buying Tokens
    function test_buy_communityToken() public {
        uint256 priceBefore = bondingCurve.getCurrentPrice();
        console.log("priceBefore:", priceBefore); //571385279910646

        // Prepare to buy tokens
        uint32 purchaseCost = 1000;
        console.log("purchaseAmount:", purchaseCost);
        uint256 requiredEth = bondingCurve.calculateRequiredEthForUsd(
            purchaseCost
        );
        console.log("requiredEth:", requiredEth);

        vm.deal(user1, 10000 ether);
        for (int i = 0; i < 20; i++) {
            vm.prank(user1);
            bondingCurve.buyToken{value: 29 ether}(purchaseCost);
        }
        uint256 currentPrice1 = bondingCurve.calculateCost(1);
        console.log("currentPrice1:", currentPrice1);
        bondingCurve.buyToken{value: 0.4 ether}(400);
        console.log("1");
        bondingCurve.buyToken{value: 0.17 ether}(450);
        console.log("2");
        bondingCurve.buyToken{value: 1.3 ether}(3500);
        console.log("3");
        bondingCurve.buyToken{value: 13 ether}(36000);
        console.log("4");
        bondingCurve.buyToken{value: 6 ether}(4000);
        console.log("5");
        bondingCurve.buyToken{value: 1.5 ether}(4000);
        console.log("6");
        bondingCurve.buyToken{value: 1.6 ether}(4400);
        console.log("7");
        // bondingCurve.buyToken{value: 1.6 ether}(4400);

        // vm.prank(user1);

        // bondingCurve.buyToken{value: 3 ether}(9000);

        // console.log("8");
        bondingCurve.buyToken{value: 1.4 ether}(3500);
        bondingCurve.buyToken{value: 0.55 ether}(1500);

        uint256 currentPrice = bondingCurve.getCurrentPrice(); //6412999996
        console.log("currentPrice:", currentPrice); //0.000000000300000000
        console.log("activeSupply:", bondingCurve.activeSupply());
        (, , , , , , uint fundingRaised) = bondingCurve.communityCoinDeets(); //300000000
        console.log("ethaccrued:", fundingRaised);
        console.log(
            "currentmrketcap:",
            ((currentPrice * bondingCurve.activeSupply()) / 1e36) * 3240
        );
        //268279.279632

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
        uint32 tokenQty = 1000;

        // Try to buy with insufficient ETH
        vm.prank(user1);
        vm.expectRevert(
            CultureBotBondingCurve.CBP__IncorrectCostValue.selector
        );
        bondingCurve.buyToken{value: 0 ether}(tokenQty);
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
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert(
            CultureBotBondingCurve.CBP__BondingCurveAlreadyGraduated.selector
        );
        bondingCurve.buyToken{value: 1 ether}(10);
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

        uint256 cost = bondingCurve.calculateCost(_tokens);

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
        uint256 correspondingEthValue = bondingCurve.calculateCost(numTokens);
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
        vm.prank(address(factory));
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
        vm.startPrank(address(factory));
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

    function test_update_admin() public {
        vm.prank(deployer);
        bondingCurve.updateAdmin(owner);
    }

    function test_revert_if_non_admin() public {
        vm.expectRevert();
        bondingCurve.updateAdmin(owner);
    }

    function test_claimRewards_withActualValuess() public {
        uint256 index = 0;
        uint256 amount = 25000000000000000000;
        address user = 0xEE67f1EF03741a0032A5c9Ccb74997CE910F4358;
        bytes32 merkleRoot = 0x463018a26eb5748d93cfd621e3d8ee54c6c698f188b222af6b838cff42480de9;
        bytes32[] memory proof = new bytes32[](2);
        proof[
            0
        ] = 0x2d50498a77cc027df885808412c3cf1dd32ae583819fbf5f051ee2d93440e1cc;
        proof[
            1
        ] = 0xc8b9dcce75eabf32f41147d1a5661627f18405a7599ecb5f074f122f23acbb75;

        vm.prank(address(factory));
        bondingCurve.claimRewards(index, amount, user, proof, merkleRoot);

        //uint256 index, uint256 amount, address toAddress, bytes32[] calldata proof, bytes32 merkleRoot
    }
}
