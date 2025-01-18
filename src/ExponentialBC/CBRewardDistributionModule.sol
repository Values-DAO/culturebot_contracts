// SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import "./Enum.sol";

interface ISafe {
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) external returns (bool success);
}

contract CBRewardDistributionModule is Ownable {
    using BitMaps for BitMaps.BitMap;

    error CBR__OnlySafe();
    error CBR__InvalidAddress();
    error CBR__RewardAlreadyClaimed();

    // Bitmap to track claimed rewards
    BitMaps.BitMap private rewardClaimList;

    // Safe address
    address public safe;

    // Delegate address (optional, for updating Merkle root)
    address public delegate;

    mapping(address tokenAddy => bytes32 merkleRoot) public tokenToMerkleRoot;

    // Events
    event RewardClaimed(
        address indexed claimant,
        uint256 index,
        uint256 amount
    );
    event MerkleRootUpdated(bytes32 newMerkleRoot, address tokenAddress);
    event DelegateUpdated(address newDelegate);

    // Modifier to restrict access to the delegate
    modifier onlyDelegate() {
        require(msg.sender == delegate, "Only delegate can call this function");
        _;
    }

    // Constructor to initialize the module with the Safe address
    constructor(address _safe) Ownable(msg.sender) {
        if (_safe == address(0)) revert CBR__InvalidAddress();
        safe = _safe;
    }

    /// @dev Allows the Safe to set or update the delegate address.
    /// @param _delegate The address of the delegate.
    function setDelegate(address _delegate) external {
        delegate = _delegate;
        emit DelegateUpdated(_delegate);
    }

    /// @dev Allows the delegate to update the Merkle root for reward distribution.
    /// @param _merkleRoot The new Merkle root.
    /// @param tokenAddress The address of the corresponding token.
    function updateMerkleRoot(
        address tokenAddress,
        bytes32 _merkleRoot
    ) external onlyDelegate {
        tokenToMerkleRoot[tokenAddress] = _merkleRoot;

        emit MerkleRootUpdated(_merkleRoot, tokenAddress);
    }

    /// @dev Allows users to claim their rewards.
    /// @param proof The Merkle proof for the claim.
    /// @param index The index of the reward in the Merkle tree.
    /// @param amount The amount of tokens to claim.
    function claimRewards(
        address toAddress,
        address tokenAddy,
        bytes32[] calldata proof,
        uint256 index,
        uint256 amount
    ) external onlyDelegate {
        // Ensure the reward has not been claimed
        if (rewardClaimList.get(index)) revert CBR__RewardAlreadyClaimed();

        // Verify the Merkle proof
        _verifyProof(proof, index, amount, toAddress, tokenAddy);

        // Mark the reward as claimed
        rewardClaimList.set(index);

        // Transfer the tokens to the claimant
        _transferTokens(tokenAddy, toAddress, amount);

        // Emit an event
        emit RewardClaimed(toAddress, index, amount);
    }

    /// @dev Internal function to verify the Merkle proof.
    /// @param proof The Merkle proof.
    /// @param index The index of the reward in the Merkle tree.
    /// @param amount The amount of tokens to claim.
    /// @param claimant The address of the claimant.
    function _verifyProof(
        bytes32[] memory proof,
        uint256 index,
        uint256 amount,
        address claimant,
        address tokenAddress
    ) private view {
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(claimant, index, amount)))
        );

        require(
            MerkleProof.verify(proof, tokenToMerkleRoot[tokenAddress], leaf),
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

    /// @dev Checks if a reward has been claimed.
    /// @param index The index of the reward in the Merkle tree.
    /// @return True if the reward has been claimed, false otherwise.
    function isRewardClaimed(uint256 index) external view returns (bool) {
        return rewardClaimList.get(index);
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
