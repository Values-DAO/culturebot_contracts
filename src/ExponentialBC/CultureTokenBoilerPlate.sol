//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CultureBotTokenBoilerPlate is ERC20, Ownable {
    //error
    error TBP__InvalidParams();
    error TBP__CantExceedMaxSupply();
    error TBP__OnlyFactoryCanAccess();
    error TBP__OnlyAuthorisedCanAccess();

    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;
    uint256 public immutable max_supply;
    uint256 private constant DECIMALS = 1e18;

    address private factory;

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
            _mint(allocationAddys[i], allocationAmount[i] * DECIMALS);
        }
    }

    function tokenMint(address caller, uint256 amount) external onlyFactory {
        if (totalSupply() + amount > max_supply)
            revert TBP__CantExceedMaxSupply();
        _mint(caller, amount);
    }

    function tokenBurn(address caller, uint256 amount) external {
        _burn(caller, amount);
    }

    function getFactory() external view returns (address) {
        return factory;
    }

    function tokenTransfer(
        uint256 amountToTransfer,
        address toAddress
    ) external {
        transferFrom(address(this), toAddress, amountToTransfer);
    }
}
