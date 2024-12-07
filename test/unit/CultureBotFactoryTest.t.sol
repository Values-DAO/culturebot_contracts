// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {CultureBotFactory} from "src/CultureBotFactory.sol";
import {CultureBotTokenBoilerPlate} from "src/CultureBotTokenBoilerPlate.sol";
import {BancorFormula} from "src/BancorFormula/BancorFormula.sol";
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

        factory.init(
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
        vm.prank(user1);
        reserveToken.mint(user1, 1000 * 10 ** 6);

        vm.prank(user1);
        reserveToken.approve(address(factory), MAXIMUM_SUPPLY * 10 ** 6);

        // Mint tokens
        vm.prank(user1);
        console.log("useeer1:", user1);
        factory.mint(1000 * 10 ** 6, communityId);

        address tokenAddress = factory.communityToToken(communityId);
        CultureBotTokenBoilerPlate token = CultureBotTokenBoilerPlate(
            tokenAddress
        );

        assertTrue(token.balanceOf(user1) > 0, "User should receive tokens");
    }

    // Retirement Tests
    function test_retireTokens() public {
        // Setup token and minting
        vm.startPrank(creator);

        factory.init(
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
        factory.mint(1000 * 10 ** 6, communityId);

        address tokenAddress = factory.communityToToken(communityId);
        CultureBotTokenBoilerPlate token = CultureBotTokenBoilerPlate(
            tokenAddress
        );

        // Approve factory to spend tokens
        token.approve(address(factory), token.balanceOf(user1));

        // Retire tokens
        uint256 initialBalance = reserveToken.balanceOf(user1);
        console.log("initialBalance:", initialBalance);

        factory.retire(token.balanceOf(user1) / 2, communityId);

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

        factory.init(
            "TestToken",
            "TST",
            allocationAddresses,
            allocationAmounts
        );

        bytes32 communityId = keccak256(
            abi.encode(creator, "TestToken", "TST", block.number)
        );
        reserveToken.mint(address(factory), 10000 * 10 ** 6);
        vm.stopPrank();

        // Check initial price
        uint256 initialPrice = factory.price(communityId);
        console.log("initialPrice:", initialPrice);
        assertTrue(initialPrice > 0, "Initial price should be positive");
    }

    // Graduation Market Cap Test
    function test_graduationMarketCap() public {
        // Setup token
        vm.startPrank(creator);

        factory.init(
            "TestToken",
            "TST",
            allocationAddresses,
            allocationAmounts
        );

        bytes32 communityId = keccak256(
            abi.encode(creator, "TestToken", "TST", block.number)
        );

        console.logBytes32(communityId);
        vm.stopPrank();

        // Prepare user
        vm.startPrank(user1);
        reserveToken.mint(user1, MAXIMUM_SUPPLY * 10 ** 6);

        reserveToken.approve(address(factory), MAXIMUM_SUPPLY * 10 ** 6);

        // Multiple minting attempts
        for (uint i = 0; i < 69; i++) {
            factory.mint(1000, communityId);
        }
        factory.mint(425, communityId);

        // Verify minting stops at market cap
        address tokenAddress = factory.communityToToken(communityId);
        CultureBotTokenBoilerPlate token = CultureBotTokenBoilerPlate(
            tokenAddress
        );

        uint256 marketCap = (factory.price(communityId) * token.totalSupply()) /
            1e9;

        console.log("marketcap:", marketCap);
        assertTrue(
            marketCap <= GRADUATION_MC,
            "Market cap should not exceed graduation point"
        );
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

        factory.init(
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
        reserveToken.mint(user1, depositAmount);

        reserveToken.approve(address(factory), depositAmount);

        // Mint tokens

        factory.mint(depositAmount, communityId);

        address tokenAddress = factory.communityToToken(communityId);
        CultureBotTokenBoilerPlate token = CultureBotTokenBoilerPlate(
            tokenAddress
        );

        assertTrue(token.balanceOf(user1) > 0, "User should receive tokens");

        vm.stopPrank();
    }

    function test_mintWithZeroDeposit() public {
        // Setup token
        vm.startPrank(creator);

        factory.init(
            "TestToken",
            "TST",
            allocationAddresses,
            allocationAmounts
        );

        bytes32 communityId = keccak256(
            abi.encode(creator, "TestToken", "TST", block.number)
        );
        vm.stopPrank();

        // Attempt to mint with zero deposit
        vm.expectRevert(CultureBotFactory.CBF__InsufficientDeposit.selector);
        factory.mint(0, communityId);
    }

    function test_retireAllTokens() public {
        // Setup and mint tokens
        vm.startPrank(creator);

        factory.init(
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
        reserveToken.mint(user1, 100000 * 10 ** 6);
        reserveToken.approve(address(factory), 100000 * 10 ** 6);

        // Mint tokens
        console.log("heyy");
        factory.mint(1000, communityId);

        address tokenAddress = factory.communityToToken(communityId);
        CultureBotTokenBoilerPlate token = CultureBotTokenBoilerPlate(
            tokenAddress
        );

        // Approve and attempt to retire all tokens
        token.approve(address(factory), token.balanceOf(user1));

        factory.retire(token.balanceOf(user1), communityId);
        vm.stopPrank();
    }

    // function test_complexTokenAllocation() public {
    //     vm.prank(creator);
    //     factory.init(
    //         "MultiAllocToken",
    //         "MAT",
    //         allocationAddresses,
    //         allocationAmounts
    //     );

    //     bytes32 communityId = keccak256(
    //         abi.encode(creator, "MultiAllocToken", "MAT", block.number)
    //     );

    //     address tokenAddress = factory.communityToToken(communityId);
    //     CultureBotBoilerPlate token = CultureBotBoilerPlate(tokenAddress);

    //     // Verify initial allocations
    //     assertEq(
    //         token.balanceOf(user1),
    //         300 * 10 ** 6,
    //         "User1 allocation incorrect"
    //     );
    //     assertEq(
    //         token.balanceOf(user2),
    //         400 * 10 ** 6,
    //         "User2 allocation incorrect"
    //     );
    //     assertEq(
    //         token.balanceOf(creator),
    //         300 * 10 ** 6,
    //         "Creator allocation incorrect"
    //     );
    // }

    function test_insufficientReserveTokenAllowance() public {
        // Setup token
        vm.startPrank(creator);
        address[] memory allocAddys = new address[](1);
        allocAddys[0] = creator;
        uint256[] memory allocAmounts = new uint256[](1);
        allocAmounts[0] = 1000 * 10 ** 6;
        factory.init("TestToken", "TST", allocAddys, allocAmounts);

        bytes32 communityId = keccak256(
            abi.encode(creator, "TestToken", "TST", block.number)
        );
        vm.stopPrank();

        // Prepare user with tokens but no approval
        vm.prank(user1);
        reserveToken.mint(msg.sender, 1000 * 10 ** 6);

        // Expect revert due to insufficient allowance
        vm.expectRevert("ERC20: insufficient allowance");
        vm.prank(user1);
        factory.mint(1000 * 10 ** 6, communityId);
    }
}
