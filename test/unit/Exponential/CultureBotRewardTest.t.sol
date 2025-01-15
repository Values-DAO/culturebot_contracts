// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CBRewardDistributionModule} from "src/ExponentialBC/CBRewardDistributionModule.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "src/ExponentialBC/Enum.sol";
import "forge-std/Test.sol";

interface ISafe {
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) external returns (bool success);
}

contract MockSafe is ISafe {
    function execTransactionFromModule(
        address,
        uint256,
        bytes calldata,
        Enum.Operation
    ) external pure returns (bool success) {
        // Simulate a successful transaction
        return true;
    }
}

contract MockERC20 is ERC20 {
    bool public failTransfers;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function setFailTransfers(bool _fail) external {
        failTransfers = _fail;
    }
}

contract CBRewardDistributionModuleTest is Test {
    CBRewardDistributionModule public module;
    MockERC20 public rewardToken;
    MockSafe public mockSafe;

    address public constant ALICE = address(0x1);
    address public constant BOB = address(0x2);
    address public constant CHARLIE = address(0x3);
    address public constant DELEGATE = address(0x4);

    // Test data for Merkle tree
    struct Claim {
        address user;
        uint256 index;
        uint256 amount;
        bytes32[] proof;
    }

    bytes32 public merkleRoot;
    mapping(address => Claim) public claims;

    function setUp() public {
        // Deploy mock contracts
        mockSafe = new MockSafe();
        rewardToken = new MockERC20("Reward Token", "RWD");
        module = new CBRewardDistributionModule(address(mockSafe));

        // Setup initial state
        vm.prank(address(mockSafe));
        module.setDelegate(DELEGATE);

        // Setup test accounts
        vm.deal(ALICE, 100 ether);
        vm.deal(BOB, 100 ether);
        vm.deal(CHARLIE, 100 ether);

        // Mint tokens to Safe
        rewardToken.mint(address(mockSafe), 1000000e18);

        vm.prank(address(mockSafe));
        rewardToken.approve(address(module), 1000000e18);

        // Setup Merkle tree data
        setupMerkleTree();
    }

    function setupMerkleTree() internal {
        // Create leaves for the Merkle tree
        bytes32[] memory leaves = new bytes32[](3);

        // Setup claims for each test user
        claims[ALICE] = Claim({
            user: ALICE,
            index: 0,
            amount: 100e18,
            proof: new bytes32[](2)
        });

        claims[BOB] = Claim({
            user: BOB,
            index: 1,
            amount: 200e18,
            proof: new bytes32[](2)
        });

        claims[CHARLIE] = Claim({
            user: CHARLIE,
            index: 2,
            amount: 300e18,
            proof: new bytes32[](2)
        });

        // Create leaves
        leaves[0] = keccak256(
            abi.encodePacked(ALICE, uint256(0), uint256(100e18))
        );
        leaves[1] = keccak256(
            abi.encodePacked(BOB, uint256(1), uint256(200e18))
        );
        leaves[2] = keccak256(
            abi.encodePacked(CHARLIE, uint256(2), uint256(300e18))
        );

        // Calculate Merkle root (simplified for testing)
        merkleRoot = keccak256(
            abi.encodePacked(
                keccak256(abi.encodePacked(leaves[0], leaves[1])),
                leaves[2]
            )
        );

        // Set proofs (simplified for testing)
        claims[ALICE].proof = new bytes32[](2);
        claims[ALICE].proof[0] = leaves[1];
        claims[ALICE].proof[1] = leaves[2];

        claims[BOB].proof = new bytes32[](2);
        claims[BOB].proof[0] = leaves[0];
        claims[BOB].proof[1] = leaves[2];

        claims[CHARLIE].proof = new bytes32[](2);
        claims[CHARLIE].proof[0] = keccak256(
            abi.encodePacked(leaves[0], leaves[1])
        );

        // Set merkle root in contract
        vm.prank(DELEGATE);
        module.updateMerkleRoot(merkleRoot);
    }

    // Test constructor
    function test_constructor() public view {
        assertEq(module.safe(), address(mockSafe));
    }

    function test_constructor_zeroAddress() public {
        vm.expectRevert(
            CBRewardDistributionModule.CBR__InvalidAddress.selector
        );
        new CBRewardDistributionModule(address(0));
    }

    // Test setDelegate
    function test_setDelegate() public {
        address newDelegate = address(0x5);
        vm.prank(address(mockSafe));
        module.setDelegate(newDelegate);
        assertEq(module.delegate(), newDelegate);
    }

    function test_setDelegate_unauthorized() public {
        address newDelegate = address(0x5);
        vm.prank(ALICE);
        vm.expectRevert(CBRewardDistributionModule.CBR__OnlySafe.selector);
        module.setDelegate(newDelegate);
    }

    // Test updateMerkleRoot
    function test_updateMerkleRoot() public {
        bytes32 newRoot = bytes32(uint256(123));
        vm.prank(DELEGATE);
        module.updateMerkleRoot(newRoot);
        assertEq(module.merkleRoot(), newRoot);
    }

    function test_updateMerkleRoot_unauthorized() public {
        bytes32 newRoot = bytes32(uint256(123));
        vm.prank(ALICE);
        vm.expectRevert("Only delegate can call this function");
        module.updateMerkleRoot(newRoot);
    }

    // Test claimRewards
    function test_claimRewards() public {
        Claim memory claim = claims[ALICE];

        uint256 initialBalance = rewardToken.balanceOf(ALICE);

        vm.prank(DELEGATE);
        module.claimRewards(
            ALICE,
            address(rewardToken),
            claim.proof,
            claim.index,
            claim.amount
        );

        assertEq(rewardToken.balanceOf(ALICE), initialBalance + claim.amount);
        assertTrue(module.isRewardClaimed(claim.index));
    }

    function testCannotClaimTwice() public {
        Claim memory claim = claims[ALICE];

        vm.prank(DELEGATE);
        module.claimRewards(
            ALICE,
            address(rewardToken),
            claim.proof,
            claim.index,
            claim.amount
        );

        vm.prank(DELEGATE);
        vm.expectRevert(
            CBRewardDistributionModule.CBR__RewardAlreadyClaimed.selector
        );
        module.claimRewards(
            ALICE,
            address(rewardToken),
            claim.proof,
            claim.index,
            claim.amount
        );
    }

    function testCannotClaimWithInvalidProof() public {
        Claim memory claim = claims[ALICE];
        claim.proof[0] = bytes32(uint256(123)); // Corrupt the proof

        vm.prank(DELEGATE);
        vm.expectRevert("Invalid Merkle proof");
        module.claimRewards(
            ALICE,
            address(rewardToken),
            claim.proof,
            claim.index,
            claim.amount
        );
    }

    function testCannotClaimWithWrongAmount() public {
        Claim memory claim = claims[ALICE];
        uint256 wrongAmount = claim.amount + 1;

        vm.prank(DELEGATE);
        vm.expectRevert("Invalid Merkle proof");
        module.claimRewards(
            ALICE,
            address(rewardToken),
            claim.proof,
            claim.index,
            wrongAmount
        );
    }

    // Test token balance check
    function testCheckRewardTokenBalance() public view {
        uint256 balance = module.checkRewardTokenBalance(address(rewardToken));
        assertEq(balance, 1000000e18);
    }

    // Fuzz testing
    function testFuzz_CannotClaimWithInvalidIndex(uint256 invalidIndex) public {
        vm.assume(invalidIndex > 2); // Assume index outside valid range

        Claim memory claim = claims[ALICE];

        vm.prank(DELEGATE);
        vm.expectRevert("Invalid Merkle proof");
        module.claimRewards(
            ALICE,
            address(rewardToken),
            claim.proof,
            invalidIndex,
            claim.amount
        );
    }

    // Test multiple claims
    function testMultipleValidClaims() public {
        // First claim
        vm.prank(ALICE);
        module.claimRewards(
            ALICE,
            address(rewardToken),
            claims[ALICE].proof,
            claims[ALICE].index,
            claims[ALICE].amount
        );

        // Second claim
        vm.prank(DELEGATE);
        module.claimRewards(
            BOB,
            address(rewardToken),
            claims[BOB].proof,
            claims[BOB].index,
            claims[BOB].amount
        );

        // Verify balances
        assertEq(rewardToken.balanceOf(ALICE), claims[ALICE].amount);
        assertEq(rewardToken.balanceOf(BOB), claims[BOB].amount);
    }

    // Test failed token transfer
    function testFailedTokenTransfer() public {
        // Deploy new mock token that will fail transfers
        MockERC20 failingToken = new MockERC20("Failing Token", "FAIL");
        failingToken.setFailTransfers(true);

        Claim memory claim = claims[ALICE];

        vm.prank(DELEGATE);
        vm.expectRevert("Token transfer failed");
        module.claimRewards(
            ALICE,
            address(failingToken),
            claim.proof,
            claim.index,
            claim.amount
        );
    }
}
