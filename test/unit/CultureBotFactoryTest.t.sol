// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {CultureBotFactory} from "src/Bancor/CultureBotFactory.sol";
import {CultureBotTokenBoilerPlate} from "src/Bancor/CultureBotTokenBoilerPlate.sol";
import {BancorFormula} from "src/Bancor/BancorFormula/BancorFormula.sol";
import {MockUSDC} from "test/Mocks/MockUSDC.sol";

contract CultureBotFactoryTest is Test {
    CultureBotFactory factory;
    BancorFormula bancorFormula;
    MockUSDC reserveToken;
    address creator;
    address user1;
    address user2;
    address public treasury;
    address public curatorTreasury;
    address public adminContract;
    // Bancor curve parameters
    uint32 constant CONNECTOR_WEIGHT = 550000; // 25%
    uint128 constant GRADUATION_MC = 69420;
    uint256 constant MAXIMUM_SUPPLY = 100_000_000_000;
    uint256 public constant TREASURY_ALLOCATION = (9 * MAXIMUM_SUPPLY) / 100;
    uint256 public constant ADMIN_ALLOCATION = (1 * MAXIMUM_SUPPLY) / 100;
    address[] allocationAddresses = new address[](3);
    uint256[] allocationAmounts = new uint256[](3);
    event Initialised(
        address creator,
        string name,
        string symbol,
        address createdTokenAddy,
        bytes32 communityId
    );

    function setUp() public {
        creator = makeAddr("creator");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        treasury = makeAddr("treasury");
        curatorTreasury = makeAddr("curatorTreasury");
        adminContract = makeAddr("adminContract");
        allocationAddresses[0] = treasury;
        allocationAddresses[1] = curatorTreasury;
        allocationAddresses[2] = adminContract;
        allocationAmounts[0] = TREASURY_ALLOCATION / 2;
        allocationAmounts[1] = TREASURY_ALLOCATION / 2;
        allocationAmounts[2] = ADMIN_ALLOCATION;
        // Deploy mock reserve token
        vm.prank(creator);
        reserveToken = new MockUSDC();
        // Deploy Bancor Formula
        vm.prank(creator);
        bancorFormula = new BancorFormula();
        // Deploy Factory
        vm.prank(creator);
        factory = new CultureBotFactory(
            CONNECTOR_WEIGHT,
            address(reserveToken),
            address(bancorFormula)
        );
    }

    // Test Contract Initialization
    function test_contractInitialization() public view {
        assertEq(
            factory.reserveWeight(),
            CONNECTOR_WEIGHT,
            "Reserve weight should match"
        );
        assertEq(
            address(reserveToken),
            factory.r_token(),
            "Reserve token address should match"
        );
    }

    // Token Creation Tests
    function test_initializeToken() public {
        vm.prank(creator);
        factory.init(
            "TestToken",
            "TST",
            allocationAddresses,
            allocationAmounts
        );
        bytes32 communityId = keccak256(
            abi.encode(creator, "TestToken", "TST", block.number)
        );
        address tokenAddress = factory.communityToToken(communityId);
        assertTrue(tokenAddress != address(0), "Token should be created");
    }

    // Minting Tests
    function test_mintTokens() public {
        // Setup token
        vm.startPrank(creator);
        address newToken = factory.init(
            "TestToken",
            "TST",
            allocationAddresses,
            allocationAmounts
        );
        vm.stopPrank();
        // Prepare user
        vm.prank(user1);
        reserveToken.mint(user1, 1000 * 10 ** 6);
        vm.prank(user1);
        reserveToken.approve(address(factory), MAXIMUM_SUPPLY * 10 ** 6);
        // Mint tokens
        vm.prank(user1);
        console.log("useeer1:", user1);
        factory.mint(1000 * 10 ** 6, newToken);
        CultureBotTokenBoilerPlate token = CultureBotTokenBoilerPlate(newToken);
        assertTrue(token.balanceOf(user1) > 0, "User should receive tokens");
    }

    // Retirement Tests
    function test_retireTokens() public {
        // Setup token and minting
        vm.startPrank(creator);
        address newToken = factory.init(
            "TestToken",
            "TST",
            allocationAddresses,
            allocationAmounts
        );
        bytes32 communityId = keccak256(
            abi.encode(creator, "TestToken", "TST", block.number)
        );
        vm.stopPrank();
        // Prepare user
        vm.startPrank(user1);
        reserveToken.mint(user1, 10000 * 10 ** 6);
        reserveToken.approve(address(factory), MAXIMUM_SUPPLY * 10 ** 6);
        // Mint tokens
        factory.mint(1000 * 10 ** 6, newToken);
        address tokenAddress = factory.communityToToken(communityId);
        CultureBotTokenBoilerPlate token = CultureBotTokenBoilerPlate(
            tokenAddress
        );
        // Approve factory to spend tokens
        token.approve(address(factory), token.balanceOf(user1));
        // Retire tokens
        uint256 initialBalance = reserveToken.balanceOf(user1);
        console.log("initialBalance:", initialBalance);
        factory.retire(token.balanceOf(user1) / 2, newToken);
        uint256 finalBalance = reserveToken.balanceOf(user1);
        console.log("finalBalance:", finalBalance);
        assertTrue(
            finalBalance > initialBalance,
            "User should receive reserve tokens"
        );
        vm.stopPrank();
    }

    // Price Calculation Tests
    function test_priceCalculation() public {
        // Setup token
        vm.startPrank(creator);
        address newToken = factory.init(
            "TestToken",
            "TST",
            allocationAddresses,
            allocationAmounts
        );
        reserveToken.mint(address(factory), 10000 * 10 ** 6);
        vm.stopPrank();
        // Check initial price
        uint256 initialPrice = factory.price(newToken);
        console.log("initialPrice:", initialPrice);
        assertTrue(initialPrice > 0, "Initial price should be positive");
    }

    // Graduation Market Cap Test
    function test_graduationMarketCap() public {
        // Setup token
        vm.startPrank(creator);
        address newToken = factory.init(
            "TestToken",
            "TST",
            allocationAddresses,
            allocationAmounts
        );
        vm.stopPrank();
        // Prepare user
        vm.startPrank(user1);
        reserveToken.mint(user1, (MAXIMUM_SUPPLY) * 10 ** 6);
        reserveToken.approve(address(factory), (MAXIMUM_SUPPLY) * 10 ** 6);
        // Verify minting stops at market cap
        CultureBotTokenBoilerPlate token = CultureBotTokenBoilerPlate(newToken);
        factory.mint(1000, newToken);
        // for (uint i = 0; i < 10; i++) {
        // }
        console.log("tokenSupply:", token.totalSupply());
        console.log("currentPrice:", factory.price(newToken)); //1000000000
        // factory.mint(408, communityId);  //10000001000000
        //9990001000000
        uint256 marketCap = (factory.price(newToken) *
            (token.totalSupply() - factory.INITIAL_ALLOCATION())) /
            factory.PRICE_PRECISION();
        console.log("marketcap:", marketCap);
        console.log("zPMC:", factory.price(newToken) * token.totalSupply());
        console.log("currentSupply:", token.totalSupply());
        // console.log("currentPrice:", factory.price(communityId));
        console.log("isTokenGraduated:", factory.isTokenGraduated(newToken));
        // assertTrue(
        //     marketCap <= GRADUATION_MC,
        //     "Market cap should not exceed graduation point"
        // );
        vm.stopPrank();
    }

    // Edge Case: Reserve Token Change
    function test_changeReserveToken() public {
        MockUSDC newReserveToken = new MockUSDC();
        vm.prank(creator);
        factory.setReserveToken(address(newReserveToken));
        assertEq(
            factory.r_token(),
            address(newReserveToken),
            "Reserve token should be updated"
        );
    }

    // Fuzzing Tests for Robust Validation
    function testFuzz_MintTokens(uint256 depositAmount) public {
        vm.assume(depositAmount > 0 && depositAmount < 1_000_000);
        // Setup token
        vm.startPrank(creator);
        address newToken = factory.init(
            "TestToken",
            "TST",
            allocationAddresses,
            allocationAmounts
        );
        vm.stopPrank();
        // Prepare user
        vm.startPrank(user1);
        reserveToken.mint(user1, depositAmount);
        reserveToken.approve(address(factory), depositAmount);
        // Mint tokens
        factory.mint(depositAmount, newToken);
        CultureBotTokenBoilerPlate token = CultureBotTokenBoilerPlate(newToken);
        assertTrue(token.balanceOf(user1) > 0, "User should receive tokens");
        vm.stopPrank();
    }

    function test_mintWithZeroDeposit() public {
        // Setup token
        vm.startPrank(creator);
        address newToken = factory.init(
            "TestToken",
            "TST",
            allocationAddresses,
            allocationAmounts
        );
        vm.stopPrank();
        // Attempt to mint with zero deposit
        vm.expectRevert(CultureBotFactory.CBF__InsufficientDeposit.selector);
        factory.mint(0, newToken);
    }

    function test_retireAllTokens() public {
        // Setup and mint tokens
        vm.startPrank(creator);
        address newToken = factory.init(
            "TestToken",
            "TST",
            allocationAddresses,
            allocationAmounts
        );
        vm.stopPrank();
        // Prepare user
        vm.startPrank(user1);
        reserveToken.mint(user1, 100000 * 10 ** 6);
        reserveToken.approve(address(factory), 100000 * 10 ** 6);
        // Mint tokens
        console.log("heyy");
        factory.mint(1000, newToken);
        CultureBotTokenBoilerPlate token = CultureBotTokenBoilerPlate(newToken);
        // Approve and attempt to retire all tokens
        token.approve(address(factory), token.balanceOf(user1));
        factory.retire(token.balanceOf(user1), newToken);
        vm.stopPrank();
    }

    function test_insufficientReserveTokenAllowance() public {
        // Setup token
        vm.startPrank(creator);
        address newToken = factory.init(
            "TestToken",
            "TST",
            allocationAddresses,
            allocationAmounts
        );
        vm.stopPrank();
        // Prepare user with tokens but no approval
        vm.prank(user1);
        reserveToken.mint(user1, 1000 * 10 ** 6);
        // Expect revert due to insufficient allowance
        vm.expectRevert();
        vm.prank(user1);
        factory.mint(1000 * 10 ** 6, newToken);
    }
}
