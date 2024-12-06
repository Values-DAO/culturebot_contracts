//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract TokenBoilerPlate is ERC20, Ownable {
    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;
    uint256 public immutable max_supply;
    bytes32 public i_merkleRoot;
    BitMaps.BitMap private _airdropList;

    address private _deployer;

    error TBP__InvalidParams();

    constructor(
        string memory name_,
        string memory symbol_,
        address deployer_,
        uint256 _max_supply,
        address[] memory allocationAddys,
        uint256[] memory allocationAmount
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        if (allocationAddys.length != allocationAmount.length)
            revert TBP__InvalidParams();
        _deployer = deployer_;
        max_supply = _max_supply;

        for (uint i = 0; i < allocationAddys.length; i++) {
            _mint(allocationAddys[i], allocationAmount[i]);
        }
    }

    function tokenMint(uint256 amount) public {
        _mint(msg.sender, amount);
    }

    function tokenBurn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    function claimProof(
        bytes32[] calldata proof,
        uint256 index,
        uint256 amount
    ) external {
        // check if already claimed
        require(!BitMaps.get(_airdropList, index), "Already claimed");

        // verify proof
        _verifyProof(proof, index, amount, msg.sender);

        // set airdrop as claimed
        BitMaps.setTo(_airdropList, index, true);

        //transfer claimable tokens
        transferFrom(address(this), msg.sender, amount);
    }

    function _verifyProof(
        bytes32[] memory proof,
        uint256 index,
        uint256 amount,
        address addr
    ) private view {
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(addr, index, amount)))
        );
        require(MerkleProof.verify(proof, i_merkleRoot, leaf), "Invalid proof");
    }

    function totalSupply() public view virtual override returns (uint256) {
        return max_supply;
    }

    function deployer() public view returns (address) {
        return _deployer;
    }

    function setMerkleRoot(bytes32 newMerkleRoot) public onlyOwner {
        i_merkleRoot = newMerkleRoot;
    }
}
