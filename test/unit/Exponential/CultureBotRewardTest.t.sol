// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CBRewardDistributionModule} from "src/ExponentialBC/CBRewardDistributionModule.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
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
    // bytes32[] public leaves;
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

    function calculateMerkleRoot(
        bytes32[] memory _leaves
    ) internal pure returns (bytes32) {
        require(_leaves.length > 0, "No leaves");

        uint256 length = _leaves.length;
        if (length == 1) {
            return _leaves[0];
        }

        bytes32[] memory nextLevel = new bytes32[]((length + 1) / 2);

        for (uint256 i = 0; i < length; i += 2) {
            if (i + 1 < length) {
                nextLevel[i / 2] = keccak256(
                    abi.encodePacked(_leaves[i], _leaves[i + 1])
                );
            } else {
                nextLevel[i / 2] = _leaves[i];
            }
        }

        return calculateMerkleRoot(nextLevel);
    }

    function setupMerkleTree() internal {
        // Create leaf nodes
        bytes32[] memory leaves = new bytes32[](3);

        // Define claims data
        address[3] memory users = [ALICE, BOB, CHARLIE];
        uint256[3] memory indices = [uint256(0), uint256(1), uint256(2)];
        uint256[3] memory amounts = [
            uint256(100e18),
            uint256(200e18),
            uint256(300e18)
        ];

        // Create leaves
        for (uint256 i = 0; i < 3; i++) {
            leaves[i] = keccak256(
                abi.encodePacked(users[i], indices[i], amounts[i])
            );
            // console.log("Leaf %s:", i);
            // console.logBytes32(leaves[i]);
        }

        // Create layer 1 (combining leaves)
        bytes32 hash01 = keccak256(abi.encodePacked(leaves[0], leaves[1]));
        // console.log("Hash01:");
        // console.logBytes32(hash01);

        // Calculate root
        merkleRoot = keccak256(abi.encodePacked(hash01, leaves[2]));
        // console.log("Root:");
        // console.logBytes32(merkleRoot);

        // Set merkle root in contract
        vm.prank(DELEGATE);
        module.updateMerkleRoot(merkleRoot);

        // Generate proofs
        // ALICE's proof (index 0): needs [leaf1, leaf2]
        bytes32[] memory aliceProof = new bytes32[](2);
        aliceProof[0] = leaves[1]; // sibling
        aliceProof[1] = leaves[2]; // next level
        claims[ALICE] = Claim({
            user: ALICE,
            index: 0,
            amount: 100e18,
            proof: aliceProof
        });

        // Log Alice's proof verification elements
        // console.log("Alice Verification Elements:");
        // console.log("Address:", uint256(uint160(ALICE)));
        // console.log("Index:", uint(0));
        // console.log("Amount:", uint(100e18));
        // console.log("Proof elements:");
        // console.logBytes32(aliceProof[0]);
        // console.logBytes32(aliceProof[1]);

        // BOB's proof (index 1): needs [leaf0, leaf2]
        bytes32[] memory bobProof = new bytes32[](2);
        bobProof[0] = leaves[0];
        bobProof[1] = leaves[2];
        claims[BOB] = Claim({
            user: BOB,
            index: 1,
            amount: 200e18,
            proof: bobProof
        });

        // CHARLIE's proof (index 2): needs [hash01]
        bytes32[] memory charlieProof = new bytes32[](1);
        charlieProof[0] = hash01;
        claims[CHARLIE] = Claim({
            user: CHARLIE,
            index: 2,
            amount: 300e18,
            proof: charlieProof
        });
    }

    function test_claimRewardsss() public {
        Claim memory claim = claims[ALICE];

        bytes32 computedLeaf = keccak256(
            abi.encodePacked(ALICE, claim.index, claim.amount)
        );
        console.log("Test Computed Leaf:");
        console.logBytes32(computedLeaf);

        console.log("Contract Merkle Root:");
        console.logBytes32(module.merkleRoot());

        // Verify each step of the proof manually
        bytes32 currentHash = computedLeaf;
        for (uint256 i = 0; i < claim.proof.length; i++) {
            console.log("Proof Step", i);
            console.log("Current Hash:");
            console.logBytes32(currentHash);
            console.log("Proof Element:");
            console.logBytes32(claim.proof[i]);
            currentHash = keccak256(
                abi.encodePacked(currentHash, claim.proof[i])
            );
            console.log("Result:");
            console.logBytes32(currentHash);
        }

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

    // Verify proof helper function
    function verifyProof(
        address account,
        uint256 index,
        uint256 amount,
        bytes32[] memory proof
    ) internal view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(account, index, amount));
        console.log("Leaf:", uint256(leaf)); // Add this if using forge console
        console.log("Root:", uint256(merkleRoot));
        return MerkleProof.verify(proof, merkleRoot, leaf);
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

    // Test claim rewards
    function test_claimRewardss() public {
        Claim memory claim = claims[ALICE];

        // Verify that the proof is valid before attempting to claim
        assertTrue(
            verifyProof(ALICE, claim.index, claim.amount, claim.proof),
            "Proof verification failed"
        );

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

    function test_claimRewards_withActualValues() public {
        vm.prank(DELEGATE);
        module.updateMerkleRoot(
            0xc36ba5cae6b6d3c0cba5ab3c18240c91387ae1dfd012e9a5f8e0d3edd779b7a5
        );
        assertEq(
            module.merkleRoot(),
            0xc36ba5cae6b6d3c0cba5ab3c18240c91387ae1dfd012e9a5f8e0d3edd779b7a5
        );
        uint256 index = 3;
        uint256 amount = 400;
        address user = 0x4567890123456789012345678901234567890123;
        bytes32[] memory proof = new bytes32[](2);
        proof[
            0
        ] = 0x9e69435cad7103c2385f49c26e7fa6a204458b9309a960c34334d119948d929a;
        proof[
            1
        ] = 0xdfbbd551fd0d1a856d630247cfd6d408a9b6274512d363ce6e722c098a5a410a;

        vm.prank(DELEGATE);
        module.claimRewards(user, address(rewardToken), proof, index, amount);
    }
}
