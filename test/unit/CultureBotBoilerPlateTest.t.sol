// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import {CultureBotTokenBoilerPlate} from "src/Bancor/CultureBotTokenBoilerPlate.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {CultureBotFactory} from "src/Bancor/CultureBotFactory.sol";

contract CultureBotTokenBoilerPlateTest is Test {
    CultureBotTokenBoilerPlate public token;
    CultureBotFactory public factory;
    // Test addresses
    address public owner;
    address public deployer;
    address public treasury;
    address public curatorTreasury;
    address public adminContract;
    address public user1;
    address public user2;
    // Merkle Tree Test Variables
    bytes32 public merkleRoot;
    bytes32[] public proof;
    uint256 public proofIndex;
    uint256 public claimAmount;
    // Constants
    uint256 public constant TOTAL_SUPPLY = 100_000_000_000 * 10 ** 18;
    uint256 public constant TREASURY_ALLOCATION = (9 * TOTAL_SUPPLY) / 100;
    uint256 public constant ADMIN_ALLOCATION = (1 * TOTAL_SUPPLY) / 100;

    function setUp() public {
        // Setup test addresses
        owner = makeAddr("owner");
        deployer = makeAddr("deployer");
        treasury = makeAddr("treasury");
        curatorTreasury = makeAddr("curatorTreasury");
        adminContract = makeAddr("adminContract");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        // Prepare allocation addresses and amounts
        address[] memory allocationAddresses = new address[](3);
        uint256[] memory allocationAmounts = new uint256[](3);
        allocationAddresses[0] = treasury;
        allocationAddresses[1] = curatorTreasury;
        allocationAddresses[2] = adminContract;
        allocationAmounts[0] = TREASURY_ALLOCATION / 2;
        allocationAmounts[1] = TREASURY_ALLOCATION / 2;
        allocationAmounts[2] = ADMIN_ALLOCATION;
        // Deploy token
        vm.prank(owner);
        token = new CultureBotTokenBoilerPlate(
            "CultureBot",
            "CULT",
            TOTAL_SUPPLY,
            allocationAddresses,
            allocationAmounts,
            address(factory)
        );
        // Prepare Merkle Tree test data
        (
            merkleRoot,
            proof,
            proofIndex,
            claimAmount
        ) = _prepareMerkleProofData();
    }

    // Internal helper to prepare Merkle Proof test data
    function _prepareMerkleProofData()
        internal
        view
        returns (bytes32, bytes32[] memory, uint256, uint256)
    {
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = keccak256(
            bytes.concat(
                keccak256(
                    abi.encode(user1, uint256(0), uint256(1000 * 10 ** 18))
                )
            )
        );
        leaves[1] = keccak256(
            bytes.concat(
                keccak256(
                    abi.encode(user2, uint256(1), uint256(2000 * 10 ** 18))
                )
            )
        );
        bytes32 root = MerkleProof.processProof(leaves, 0);
        bytes32[] memory userProof = new bytes32[](1);
        userProof[0] = leaves[1];
        return (root, userProof, 1, 2000 * 10 ** 18);
    }

    // Constructor Tests
    function test_constructor() public view {
        assertEq(token.name(), "CultureBot");
        assertEq(token.symbol(), "CULT");
        assertEq(token.factory(), address(factory));
        assertEq(token.factory(), deployer);
        assertEq(token.totalSupply(), TOTAL_SUPPLY);
    }

    function test_initialAllocations() public view {
        assertEq(token.balanceOf(treasury), TREASURY_ALLOCATION / 2);
        assertEq(token.balanceOf(curatorTreasury), TREASURY_ALLOCATION / 2);
        assertEq(token.balanceOf(adminContract), ADMIN_ALLOCATION);
    }

    function test_constructorRevertOn_mismatchedArrays() public {
        address[] memory incompletAddresses = new address[](2);
        uint256[] memory incompletAmounts = new uint256[](3);
        vm.expectRevert(CultureBotTokenBoilerPlate.TBP__InvalidParams.selector);
        new CultureBotTokenBoilerPlate(
            "CultureBot",
            "CULT",
            TOTAL_SUPPLY,
            incompletAddresses,
            incompletAmounts,
            address(factory)
        );
    }

    // Mint Tests
    function test_tokenMint() public {
        uint256 mintAmount = 1000 * 10 ** 18;
        vm.prank(address(factory));
        token.tokenMint(msg.sender, mintAmount);
        assertEq(token.balanceOf(address(factory)), mintAmount);
    }

    // Burn Tests
    function test_tokenBurn() public {
        uint256 initialMintAmount = 2000 * 10 ** 18;
        vm.prank(address(factory));
        token.tokenMint(msg.sender, initialMintAmount);
        uint256 burnAmount = 1000 * 10 ** 18;
        vm.prank(address(factory));
        token.tokenBurn(msg.sender, burnAmount);
        assertEq(
            token.balanceOf(address(factory)),
            initialMintAmount - burnAmount
        );
        assertEq(token.balanceOf(msg.sender), initialMintAmount - burnAmount);
    }

    // Merkle Root Tests
    function test_setMerkleRoot() public {
        bytes32 newMerkleRoot = keccak256(abi.encodePacked("new root"));
        vm.prank(owner);
        token.setMerkleRoot(newMerkleRoot);
        assertEq(token.i_merkleRoot(), newMerkleRoot);
    }

    function test_setMerkleRootFails_forNonOwner() public {
        bytes32 newMerkleRoot = keccak256(abi.encodePacked("new root"));
        vm.prank(user1);
        vm.expectRevert();
        token.setMerkleRoot(newMerkleRoot);
    }

    // Reward Claim Tests
    function test_rewardClaim() public {
        // First set the merkle root
        vm.prank(owner);
        token.setMerkleRoot(merkleRoot);
        // Fund the contract with claimable tokens
        vm.prank(owner);
        token.tokenMint(msg.sender, claimAmount);
        // Claim rewards
        vm.prank(user2);
        token.claimRewards(proof, proofIndex, claimAmount);
        assertEq(token.balanceOf(user2), claimAmount);
    }

    // Negative Test Cases
    function testCannotClaimTwice() public {
        // Set merkle root
        vm.prank(owner);
        token.setMerkleRoot(merkleRoot);
        // Fund the contract
        vm.prank(owner);
        token.tokenMint(msg.sender, claimAmount);
        // First claim
        vm.prank(user2);
        token.claimRewards(proof, proofIndex, claimAmount);
        // Second claim should fail
        vm.prank(user2);
        vm.expectRevert("Already claimed");
        token.claimRewards(proof, proofIndex, claimAmount);
    }

    function testInvalidMerkleProofClaim() public {
        // Set merkle root
        vm.prank(owner);
        token.setMerkleRoot(merkleRoot);
        // Fund the contract
        vm.prank(owner);
        token.tokenMint(msg.sender, claimAmount);
        // Invalid proof
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256(abi.encodePacked("invalid"));
        vm.prank(user1);
        vm.expectRevert("Invalid proof");
        token.claimRewards(invalidProof, proofIndex, claimAmount);
    }
}
