//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract CultureBotTokenBoilerPlate is ERC20, Ownable {
    //error
    error TBP__InvalidParams();
    error TBP__OnlyFactoryCanAccess();

    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;
    uint256 public immutable max_supply;
    bytes32 public i_merkleRoot;
    BitMaps.BitMap private rewardClaimList;

    address public factory;

    modifier onlyFactory() {
        if (msg.sender != factory) revert TBP__OnlyFactoryCanAccess();
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 _max_supply,
        address[] memory allocationAddys,
        uint256[] memory allocationAmount,
        address _factory
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        if (allocationAddys.length != allocationAmount.length)
            revert TBP__InvalidParams();
        factory = _factory;
        max_supply = _max_supply;

        for (uint i = 0; i < allocationAddys.length; i++) {
            _mint(allocationAddys[i], allocationAmount[i]);
        }
    }

    function tokenMint(address caller, uint256 amount) public onlyFactory {
        _mint(caller, amount);
    }

    function tokenBurn(address caller, uint256 amount) public onlyFactory {
        _burn(caller, amount);
    }

    function claimRewards(
        bytes32[] calldata proof,
        uint256 index,
        uint256 amount
    ) external {
        // check if already claimed
        require(!BitMaps.get(rewardClaimList, index), "Already claimed");

        // verify proof
        _verifyProof(proof, index, amount, msg.sender);

        // set rewards as claimed
        BitMaps.setTo(rewardClaimList, index, true);

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

    function getFactory() public view returns (address) {
        return factory;
    }

    function setMerkleRoot(bytes32 newMerkleRoot) public onlyFactory {
        i_merkleRoot = newMerkleRoot;
    }
}
