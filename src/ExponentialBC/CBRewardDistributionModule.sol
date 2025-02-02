// SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import "./Enum.sol";

interface ISafe {
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) external returns (bool success);
}

contract CBRewardDistributionModule is AccessControl {
    error CBR__OnlySafe();
    error CBR__InvalidAddress();
    error CBR__RewardAlreadyClaimed();

    // Safe address
    address public safe;

    // Delegate address (optional, for updating Merkle root)
    address public delegate;

    /// @notice Last reward campaign timestamp
    uint256 public lastRewardCampaignTimestamp;
    /// @notice weekly root hash
    bytes32 private weeklyRootTimestampHash;

    uint256 private constant ROOT_AND_HASH_UPDATE_INTERVAL = 7 days;
    bytes32 public constant REWARD_DISTRIBUTION_ROLE =
        keccak256("REWARD_DISTRIBUTION_ROLE");
    address public constant REWARD_DISTRIBUTOR =
        0x98278DF51402ED4cE090cCB2D6AF23f0989F78cE;

    mapping(address => mapping(bytes32 => mapping(address => bool)))
        public weeklyRewardClaimed;

    mapping(address tokenAddy => bytes32 merkleRoot) public tokenToMerkleRoot;

    // Events
    event WeeklyRootUpdated(
        address tokenAddy,
        bytes32 newRoot,
        uint256 timestamp
    );
    event RewardDistributed(
        address indexed claimant,
        address tokenAddress,
        uint256 amount
    );
    event DelegateUpdated(address newDelegate);

    // Modifier to restrict access to the delegate
    modifier onlyDelegate() {
        require(msg.sender == delegate, "Only delegate can call this function");
        _;
    }

    // Constructor to initialize the module with the Safe address
    constructor(address _safe) {
        if (_safe == address(0)) revert CBR__InvalidAddress();
        safe = _safe;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(REWARD_DISTRIBUTION_ROLE, REWARD_DISTRIBUTOR);
    }

    /// @dev Allows users to claim their rewards.
    /// @param proof The Merkle proof for the claim.
    /// @param merkleRoot The Merkle root for the claim.
    /// @param amount The amount of tokens to claim.
    function distributeRewards(
        address toAddress,
        address tokenAddy,
        bytes32[] calldata proof,
        bytes32 merkleRoot,
        uint256 amount
    ) external onlyRole(REWARD_DISTRIBUTION_ROLE) {
        if (
            block.timestamp - lastRewardCampaignTimestamp >=
            ROOT_AND_HASH_UPDATE_INTERVAL
        ) {
            updateWeeklyRootAndHash(tokenAddy, merkleRoot);
        }
        // Ensure the reward has not been claimed
        if (weeklyRewardClaimed[tokenAddy][weeklyRootTimestampHash][toAddress])
            revert CBR__RewardAlreadyClaimed();
        // Verify the Merkle proof
        _verifyProof(amount, toAddress, merkleRoot, proof);

        weeklyRewardClaimed[tokenAddy][weeklyRootTimestampHash][
            toAddress
        ] = true;

        // Emit an event
        emit RewardDistributed(toAddress, tokenAddy, amount);

        // Transfer the tokens to the claimant
        _transferTokens(tokenAddy, toAddress, amount);
    }

    /// @notice Updates the reward distributor address
    /// @dev Only callable by admin role. Revokes role from current distributor and grants to new one
    /// @param newDistributor Address of the new reward distributor
    function updateRewardDistributor(
        address newDistributor
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(REWARD_DISTRIBUTION_ROLE, REWARD_DISTRIBUTOR);
        _grantRole(REWARD_DISTRIBUTION_ROLE, newDistributor);
    }

    /// @dev Allows the Safe to set or update the delegate address.
    /// @param _delegate The address of the delegate.
    function setDelegate(address _delegate) external {
        delegate = _delegate;
        emit DelegateUpdated(_delegate);
    }

    /// @dev external function to update the weekly root and hash
    /// @param newRoot The new root to update§
    function updateWeeklyRootAndHash(
        address tokenAddy,
        bytes32 newRoot
    ) private {
        emit WeeklyRootUpdated(tokenAddy, newRoot, block.timestamp);
        lastRewardCampaignTimestamp = block.timestamp;
        weeklyRootTimestampHash = keccak256(
            abi.encodePacked(newRoot, block.timestamp)
        );
    }

    /// @dev Internal function to verify the Merkle proof.
    /// @param amount The amount of tokens to claim.
    /// @param claimant The address of the claimant.
    /// @param merkleRoot The Merkle root.
    /// @param proof The Merkle proof.
    function _verifyProof(
        uint256 amount,
        address claimant,
        bytes32 merkleRoot,
        bytes32[] calldata proof
    ) private pure {
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(claimant, amount)))
        );

        require(
            MerkleProof.verify(proof, merkleRoot, leaf),
            "Invalid Merkle proof"
        );
    }

    /// @dev Internal function to transfer tokens from the Safe to the claimant.
    /// @param to The address to transfer tokens to.
    /// @param amount The amount of tokens to transfer.
    function _transferTokens(
        address tokenAddy,
        address to,
        uint256 amount
    ) private {
        // Encode the transfer function call
        bytes memory data = abi.encodeWithSignature(
            "transfer(address,uint256)",
            to,
            amount
        );

        // Execute the transfer via the Safe
        require(
            ISafe(safe).execTransactionFromModule(
                tokenAddy,
                0,
                data,
                Enum.Operation.Call
            ),
            "Token transfer failed"
        );
    }

    /**
     * @notice Updates the address of the safe.
     * @dev This function can only be called by the owner.
     * @param _safe The new address of the safe.
     */
    function updateSafe(address _safe) external onlyDelegate {
        if (_safe == address(0)) revert CBR__InvalidAddress();
        safe = _safe;
    }

    /// @notice Checks if a reward has been claimed for a specific token and address
    /// @dev Returns the claim status from weeklyRewardClaimed mapping using current root hash
    /// @param tokenAddy The address of the reward token
    /// @param toAddress The address to check the claim status for
    /// @return True if the reward has been claimed, false otherwise
    function isRewardClaimed(
        address tokenAddy,
        address toAddress
    ) external view returns (bool) {
        return
            weeklyRewardClaimed[tokenAddy][weeklyRootTimestampHash][toAddress];
    }

    /**
     * @notice Checks the balance of the specified reward token in the contract.
     * @param _token The address of the token to check the balance of.
     * @return The balance of the specified token in the contract.
     */
    function checkRewardTokenBalance(
        address _token
    ) public view returns (uint256) {
        return IERC20(_token).balanceOf(address(safe));
    }
}
