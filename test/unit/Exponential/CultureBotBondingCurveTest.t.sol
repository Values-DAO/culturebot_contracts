// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {CultureBotBondingCurve} from "src/ExponentialBC/CultureBotBondingCurve.sol";
import {CultureBotTokenBoilerPlate} from "src/ExponentialBC/CultureTokenBoilerPlate.sol";
import {CultureBotFactory} from "src/ExponentialBC/CultureBotFactory.sol";
import {AggregatorV3Interface} from "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

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

    function setUp() public {
        // Setup test addresses
        deployer = makeAddr("deployer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Mock Chainlink Price Feed
        mockPriceFeed = AggregatorV3Interface(makeAddr("mockPriceFeed"));

        // Setup factory with mock price feed
        vm.prank(deployer);
        factory = new CultureBotFactory(mockPriceFeed);

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
            string memory description,
            uint fundingRaised,
            address tokenAddress,
            address creatorAddress
        ) = bondingCurve.addressToTokenMapping(communityToken);

        assertEq(name, "TestMemeCoin");
        assertEq(symbol, "TMC");
        assertEq(description, "Test Meme Coin Description");
        assertEq(fundingRaised, 0);
        assertEq(tokenAddress, address(memeToken));
        assertEq(creatorAddress, deployer);
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
    function test_buyCommunity_token() public {
        // Fund the contract with ETH

        uint256 priceBefore = bondingCurve.calculateCost(
            bondingCurve.activeSupply(),
            1
        );
        console.log("priceBefore:", priceBefore);

        // Prepare to buy tokens
        uint256 tokenQty = 100000;
        //3000000
        uint256 requiredEth = bondingCurve.calculateCost(0, tokenQty);
        console.log("requiredEth:", requiredEth);

        console.log(
            "numTokensForEth:",
            bondingCurve.calculateTokensForEth(0, requiredEth)
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
        bondingCurve.buyToken{value: 0.4 ether}(address(memeToken), 100000000);
        console.log("3");
        bondingCurve.buyToken{value: 0.65 ether}(
            address(memeToken),
            1000000000
        );
        console.log("4");
        bondingCurve.buyToken{value: 1.61 ether}(address(memeToken), 999999999);
        console.log("5");
        bondingCurve.buyToken{value: 0.193 ether}(address(memeToken), 99999999);
        console.log("6");
        bondingCurve.buyToken{value: 0.63 ether}(address(memeToken), 99999999);
        console.log("7");
        bondingCurve.buyToken{value: 0.226 ether}(address(memeToken), 99999999);
        for (int i = 0; i < 7; i++) {
            vm.prank(user1);

            bondingCurve.buyToken{value: 3 ether}(
                address(memeToken),
                1000000000
            );
        } //0.000000004502362662
        //0.00000000032138437
        //11412999996
        uint256 currentPrice = bondingCurve.calculateCost(
            bondingCurve.activeSupply(), //2112999999
            1
        ); //6412999996
        console.log("currentPrice:", currentPrice); //0.000000000300000000
        console.log("activeSupply:", bondingCurve.activeSupply());
        (, , , uint fundingRaised, , ) = bondingCurve.addressToTokenMapping(
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
        uint256 requiredEth = bondingCurve.calculateCost(0, tokenQty);

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
        vm.assume(_supply < MAX_SUPPLY / 10 ** 18);
        vm.assume(
            _tokens > 0 &&
                _tokens < (MAX_SUPPLY - _supply * 10 ** 18) / 10 ** 18
        );

        uint256 cost = bondingCurve.calculateCost(_supply, _tokens);
        console.log("coosts:", cost);

        // Basic sanity checks
        assertGt(cost, 0, "Cost should always be positive");
    }
}
