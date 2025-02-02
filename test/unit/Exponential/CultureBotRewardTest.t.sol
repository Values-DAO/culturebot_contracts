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
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public DELEGATE = address(0x4);
    // Test data for Merkle tree
    struct Claim {
        address user;
        uint256 index;
        uint256 amount;
        bytes32[] proof;
    }
    bytes32 public merkleRoot;
    bytes32[] public leaves;
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
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
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
        // Initialize leaves array
        leaves = new bytes32[](3);
        // Create leaves for the Merkle tree using the correct encoding
        leaves[0] = keccak256(
            bytes.concat(
                keccak256(abi.encode(alice, uint256(0), uint256(100e18)))
            )
        );
        leaves[1] = keccak256(
            bytes.concat(
                keccak256(abi.encode(bob, uint256(1), uint256(200e18)))
            )
        );
        leaves[2] = keccak256(
            bytes.concat(
                keccak256(abi.encode(charlie, uint256(2), uint256(300e18)))
            )
        );
        // Calculate intermediate nodes
        bytes32 hash01 = keccak256(
            bytes.concat(keccak256(abi.encode(leaves[0], leaves[1])))
        );
        bytes32 hash2 = leaves[2];
        // Calculate root
        merkleRoot = keccak256(
            bytes.concat(keccak256(abi.encode(hash01, hash2)))
        );
        // Generate proofs
        // For alice (index 0)
        bytes32[] memory aliceProof = new bytes32[](2);
        aliceProof[0] = leaves[1];
        aliceProof[1] = hash2;
        claims[alice] = Claim({
            user: alice,
            index: 0,
            amount: 100e18,
            proof: aliceProof
        });
        // For bob (index 1)
        bytes32[] memory bobProof = new bytes32[](2);
        bobProof[0] = leaves[0];
        bobProof[1] = hash2;
        claims[bob] = Claim({
            user: bob,
            index: 1,
            amount: 200e18,
            proof: bobProof
        });
        // For charlie (index 2)
        bytes32[] memory charlieProof = new bytes32[](1);
        charlieProof[0] = hash01;
        claims[charlie] = Claim({
            user: charlie,
            index: 2,
            amount: 300e18,
            proof: charlieProof
        });
    }

    // Verify proof helper function
    function verifyProof(
        address account,
        uint256 index,
        uint256 amount,
        bytes32[] memory proof
    ) internal view returns (bool) {
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(account, index, amount)))
        );
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
        vm.prank(alice);
        vm.expectRevert(CBRewardDistributionModule.CBR__OnlySafe.selector);
        module.setDelegate(newDelegate);
    }

    // Test claim rewards
    function test_claimRewardss() public {
        Claim memory claim = claims[alice];
        // Verify that the proof is valid before attempting to claim
        assertTrue(
            verifyProof(alice, claim.index, claim.amount, claim.proof),
            "Proof verification failed"
        );
        uint256 initialBalance = rewardToken.balanceOf(alice);
        vm.prank(DELEGATE);
        module.distributeRewards(
            alice,
            address(rewardToken),
            claim.proof,
            merkleRoot,
            claim.amount
        );
        assertEq(rewardToken.balanceOf(alice), initialBalance + claim.amount);
        assertTrue(module.isRewardClaimed(address(rewardToken), alice));
    }

    // Test claimRewards
    function test_claimRewards() public {
        Claim memory claim = claims[alice];
        uint256 initialBalance = rewardToken.balanceOf(alice);
        vm.prank(DELEGATE);
        module.distributeRewards(
            alice,
            address(rewardToken),
            claim.proof,
            merkleRoot,
            claim.amount
        );
        assertEq(rewardToken.balanceOf(alice), initialBalance + claim.amount);
        assertTrue(module.isRewardClaimed(address(rewardToken), alice));
    }

    function testCannotClaimTwice() public {
        Claim memory claim = claims[alice];
        vm.prank(DELEGATE);
        module.distributeRewards(
            alice,
            address(rewardToken),
            claim.proof,
            merkleRoot,
            claim.amount
        );
        vm.prank(DELEGATE);
        vm.expectRevert(
            CBRewardDistributionModule.CBR__RewardAlreadyClaimed.selector
        );
        module.distributeRewards(
            alice,
            address(rewardToken),
            claim.proof,
            merkleRoot,
            claim.amount
        );
    }

    function testCannotClaimWithInvalidProof() public {
        Claim memory claim = claims[alice];
        claim.proof[0] = bytes32(uint256(123)); // Corrupt the proof
        vm.prank(DELEGATE);
        vm.expectRevert("Invalid Merkle proof");
        module.distributeRewards(
            alice,
            address(rewardToken),
            claim.proof,
            merkleRoot,
            claim.amount
        );
    }

    function testCannotClaimWithWrongAmount() public {
        Claim memory claim = claims[alice];
        uint256 wrongAmount = claim.amount + 1;
        vm.prank(DELEGATE);
        vm.expectRevert("Invalid Merkle proof");
        module.distributeRewards(
            alice,
            address(rewardToken),
            claim.proof,
            merkleRoot,
            wrongAmount
        );
    }

    // Test token balance check
    function testCheckRewardTokenBalance() public view {
        uint256 balance = module.checkRewardTokenBalance(address(rewardToken));
        assertEq(balance, 1000000e18);
    }

    // Fuzz testing
    function testFuzz_CannotClaimWithInvalidIndex(bytes32 invalidRoot) public {
        Claim memory claim = claims[alice];
        vm.prank(DELEGATE);
        vm.expectRevert("Invalid Merkle root");
        module.distributeRewards(
            alice,
            address(rewardToken),
            claim.proof,
            invalidRoot,
            claim.amount
        );
    }

    // Test multiple claims
    function testMultipleValidClaims() public {
        // First claim
        vm.prank(alice);
        module.distributeRewards(
            alice,
            address(rewardToken),
            claims[alice].proof,
            merkleRoot,
            claims[alice].amount
        );
        // Second claim
        vm.prank(DELEGATE);
        module.distributeRewards(
            bob,
            address(rewardToken),
            claims[bob].proof,
            merkleRoot,
            claims[bob].amount
        );
        // Verify balances
        assertEq(rewardToken.balanceOf(alice), claims[alice].amount);
        assertEq(rewardToken.balanceOf(bob), claims[bob].amount);
    }

    // Test failed token transfer
    function testFailedTokenTransfer() public {
        // Deploy new mock token that will fail transfers
        MockERC20 failingToken = new MockERC20("Failing Token", "FAIL");
        failingToken.setFailTransfers(true);
        Claim memory claim = claims[alice];
        vm.prank(DELEGATE);
        vm.expectRevert("Token transfer failed");
        module.distributeRewards(
            alice,
            address(failingToken),
            claim.proof,
            merkleRoot,
            claim.amount
        );
    }

    function test_claimRewards_withActualValues() public {
        bytes32 root = 0xaa5d581231e596618465a56aa0f5870ba6e20785fe436d5bfb82b08662ccc7c4;

        uint256 amount = 25000000000000000000;
        address user = 0x6CA6d1e2D5347Bfab1d91e883F1915560e09129D;
        bytes32[] memory proof = new bytes32[](2);
        proof[
            0
        ] = 0x0fd7c981d39bece61f7499702bf59b3114a90e66b51ba2c53abdf7b62986c00a;
        proof[
            1
        ] = 0xe5ebd1e1b5a5478a944ecab36a9a954ac3b6b8216875f6524caa7a1d87096576;
        vm.prank(address(this));
        module.distributeRewards(
            user,
            address(rewardToken),
            proof,
            root,
            amount
        );
    }
}
