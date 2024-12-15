// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CultureBotTokenBoilerPlate} from "src/Bancor/CultureBotTokenBoilerPlate.sol";
import {BancorFormula} from "src/Bancor/BancorFormula/BancorFormula.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CultureBotFactory is Ownable {
    //error
    error CBF__InsufficientDeposit();
    error CBF__TokenAlreadyGraduated();
    error CBF__ONlyCallableAfterGraduation();

    CultureBotTokenBoilerPlate tokenBoilerPlate;
    BancorFormula bancorFormulaContract;

    struct TokenDeets {
        string name;
        string symbol;
        uint256 fundsRaised;
        address tokenAddy;
        address creatorAddy;
    }

    // Reserve token. Should be a stable coin. For convenience, we'll assume USDC
    address public r_token;

    // Reserve Weight
    uint32 internal immutable _cw;
    uint128 public constant GRADUATION_MC = 69420;
    uint256 public constant MAXIMUM_SUPPLY = 100_000_000_000;
    uint256 public constant INITIAL_ALLOCATION = 100_000_000_00;
    uint256 public constant PRICE_PRECISION = 1e9;

    event Initialised(
        address creator,
        string name,
        string symbol,
        address createdTokenAddy,
        bytes32 communityId
    );

    event Mint(address indexed by, uint256 amount, uint256 depositAmount);

    event Retire(address indexed by, uint256 amount, uint256 liquidity);

    mapping(bytes32 => address) public communityToToken;
    mapping(address => bool) public isTokenGraduated;
    mapping(address => TokenDeets) public tokenToDeets;

    modifier ifNotGraduated(address tokenAddy) {
        if (isTokenGraduated[tokenAddy] == true)
            revert CBF__TokenAlreadyGraduated();
        _;
    }

    constructor(
        uint32 cw_,
        address r_token_,
        address bancorFormula
    ) Ownable(msg.sender) {
        _cw = cw_;
        r_token = r_token_;
        bancorFormulaContract = BancorFormula(bancorFormula);
    }

    /// @notice initialize token with allocation mints and reserve currency.
    /// @dev Initializes Bancor formula contract. Mints single token.
    /// Note Must call after construction, and before calling any other functions
    function init(
        string memory name_,
        string memory symbol_,
        address[] memory allocationAddys,
        uint256[] memory allocationAmount
    ) public payable returns (address newToken) {
        newToken = address(
            new CultureBotTokenBoilerPlate(
                name_,
                symbol_,
                MAXIMUM_SUPPLY,
                allocationAddys,
                allocationAmount,
                address(this)
            )
        );
        bytes32 communityId = keccak256(
            abi.encode(msg.sender, name_, symbol_, block.number)
        );
        communityToToken[communityId] = newToken;
        tokenToDeets[newToken] = TokenDeets(
            name_,
            symbol_,
            0,
            newToken,
            msg.sender
        );
        emit Initialised(msg.sender, name_, symbol_, newToken, communityId);
    }

    /// @notice Returns reserve balance
    /// @dev calls balanceOf in reserve token contract
    /**
     *  Note Reserve Balance, precision = 6
     *  Reserve balance will be zero initially, but in theory should be 1 reserve token.
     *  We can assume the contract has 1USDC initially, since it cannot be withdrawn anyway.
     */
    function reserveBalance() public view returns (uint256) {
        (bool success, bytes memory data) = r_token.staticcall(
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(this))
        );
        require(
            success && data.length >= 32,
            "Reserve Token Balance Check Failure"
        ); /// This is just for safety. Ideally, this requirement shouldn't fail in any circumstance.
        return abi.decode(data, (uint256)) + 1e6;
    }

    function reserveWeight() public view returns (uint32) {
        return _cw;
    }

    /// @notice Returns price at current supply
    /// @dev price = reserve_balance / (reserve_weight * total_supply)

    function price(address tokenAddy) public view returns (uint256) {
        uint256 tokenPerDollar = purchaseTargetAmount(1, tokenAddy);
        return ((1 * PRICE_PRECISION) / tokenPerDollar);
    }

    /// @notice Returns expected price at the expected supply
    function expectedPrice(
        address tokenAddy,
        uint256 reserveDeposit
    ) public view returns (uint256) {
        uint256 expectedTokenSupplyAddition = purchaseTargetAmount(
            reserveDeposit,
            tokenAddy
        );

        uint256 tokensPerDollar = bancorFormulaContract.purchaseTargetAmount(
            (CultureBotTokenBoilerPlate(tokenAddy).totalSupply() +
                expectedTokenSupplyAddition),
            (tokenToDeets[tokenAddy].fundsRaised + reserveDeposit),
            reserveWeight(),
            1
        );

        return ((1 * PRICE_PRECISION) / tokensPerDollar);
    }

    /// @notice Mints tokens pertaining to the deposited amount of reserve tokens
    /// @dev Calls mint on token contract, purchaseTargetAmount on formula contract
    /// @param deposit The deposited amount of reserve tokens
    /// Note Must approve with reserve token before calling

    function mint(
        uint256 deposit,
        address tokenAddy
    ) external payable ifNotGraduated(tokenAddy) {
        uint256 expectedSupplyAddition = purchaseTargetAmount(
            deposit,
            tokenAddy
        );

        if (deposit == 0) revert CBF__InsufficientDeposit();

        if (
            ((expectedPrice(tokenAddy, deposit) *
                ((CultureBotTokenBoilerPlate(tokenAddy).totalSupply() -
                    INITIAL_ALLOCATION) + expectedSupplyAddition)) /
                PRICE_PRECISION) >= GRADUATION_MC
        ) {
            isTokenGraduated[tokenAddy] = true;
        }

        uint256 amount = bancorFormulaContract.purchaseTargetAmount(
            CultureBotTokenBoilerPlate(tokenAddy).totalSupply(),
            (tokenToDeets[tokenAddy].fundsRaised + 1),
            reserveWeight(),
            deposit
        );

        CultureBotTokenBoilerPlate(tokenAddy).tokenMint(msg.sender, amount);

        IERC20(r_token).transferFrom(msg.sender, address(this), deposit);
        tokenToDeets[tokenAddy].fundsRaised += deposit;

        emit Mint(msg.sender, amount, deposit);
    }

    function adminMint(address tokenAddy) public onlyOwner {
        if (isTokenGraduated[tokenAddy] != true)
            revert CBF__ONlyCallableAfterGraduation();

        uint256 supplyLeftToMint = MAXIMUM_SUPPLY -
            CultureBotTokenBoilerPlate(tokenAddy).totalSupply();
        CultureBotTokenBoilerPlate(tokenAddy).tokenMint(
            tokenAddy,
            supplyLeftToMint
        );
    }

    /// @notice Retires tokens of given amount, and transfers pertaining reserve tokens to account
    /// @dev Calls burn on token contract, saleTargetAmmount on formula contract
    /// @param amount The amount of tokens being retired
    function retire(
        uint256 amount,
        address tokenAddy
    ) external payable ifNotGraduated(tokenAddy) {
        require(
            CultureBotTokenBoilerPlate(tokenAddy).totalSupply() - amount > 0,
            "BancorContinuousToken: Requested Retire Amount Exceeds Supply"
        );

        require(
            amount <=
                CultureBotTokenBoilerPlate(tokenAddy).balanceOf(msg.sender),
            "BancorContinuousToken: Requested Retire Amount Exceeds Owned"
        );
        uint256 liquidity = bancorFormulaContract.saleTargetAmount(
            CultureBotTokenBoilerPlate(tokenAddy).totalSupply(),
            (tokenToDeets[tokenAddy].fundsRaised + 1),
            reserveWeight(),
            amount
        );
        IERC20(r_token).transfer(msg.sender, liquidity);
        CultureBotTokenBoilerPlate(tokenAddy).tokenBurn(msg.sender, amount);
        emit Retire(msg.sender, amount, liquidity);
    }

    /// @notice Cost of purchasing given amount of tokens
    /// @dev Calls purchaseCost on formula contract
    /// @param amount The amount of tokens to be purchased
    function purchaseCost(
        uint256 amount,
        address tokenAddy
    ) public view returns (uint256) {
        return
            bancorFormulaContract.purchaseCost(
                CultureBotTokenBoilerPlate(tokenAddy).totalSupply(),
                (tokenToDeets[tokenAddy].fundsRaised + 1),
                reserveWeight(),
                amount
            );
    }

    /// @notice Tokens that will be minted for a given deposit
    /// @dev Calls purchaseTargetAmount on formula contract
    /// @param deposit The deposited amount of reserve tokens
    function purchaseTargetAmount(
        uint256 deposit,
        address tokenAddy
    ) public view returns (uint256) {
        return
            bancorFormulaContract.purchaseTargetAmount(
                CultureBotTokenBoilerPlate(tokenAddy).totalSupply(),
                (tokenToDeets[tokenAddy].fundsRaised + 1),
                reserveWeight(),
                deposit
            );
    }

    /// @notice Amount in reserve tokens from retiring given amount of cont. tokens
    /// @dev Calls saleTargetAmount on formula contract
    /// @param amount The amount of tokens to be retired
    function saleTargetAmount(
        uint256 amount,
        address tokenAddy
    ) public view returns (uint256) {
        require(
            CultureBotTokenBoilerPlate(tokenAddy).totalSupply() - amount > 0,
            "BancorContinuousToken: Requested Retire Amount Exceeds Supply"
        );
        return
            bancorFormulaContract.saleTargetAmount(
                CultureBotTokenBoilerPlate(tokenAddy).totalSupply(),
                (tokenToDeets[tokenAddy].fundsRaised + 1),
                reserveWeight(),
                amount
            );
    }

    /// @notice Changes reserve token address in case it is updated
    function setReserveToken(address _r_token) external onlyOwner {
        r_token = _r_token;
    }
}
