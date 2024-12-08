-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

DEFAULT_KEY := 

help:
	@echo "Usage:"
	@echo "  make deploy [ARGS=...]\n    example: make deploy ARGS=\"--network sepolia\""
	@echo ""
	@echo "  make fund [ARGS=...]\n    example: make deploy ARGS=\"--network sepolia\""

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; 

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test 

snapshot :; forge snapshot

format :; forge fmt

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

NETWORK_ARGS := --rpc-url $(ALCHEMY_RPC_URL) --private-key $(METAMASK_PRIVATE_KEY) --broadcast

ifeq ($(findstring --network ethereum,$(ARGS)),--network ethereum)
	NETWORK_ARGS := --rpc-url $(ALCHEMY_RPC_URL) --private-key $(METAMASK_PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

deploy:
	@forge script script/DeployBancorFormula.s.sol:DeployBancorFormula $(NETWORK_ARGS)
	@forge script script/DeployCultureBotFactory.s.sol:DeployCultureBotFactory $(NETWORK_ARGS)




verify:
	@forge verify-contract --chain-id 84532 --watch --constructor-args `cast abi-encode "constructor(uint32,address,address)" "$(CW)" "$(RV_TOKEN)" "$(BANCOR_FORMULA)"` --etherscan-api-key $(ETHERSCAN_API_KEY) --compiler-version 0.8.24 0x6125E6895a1D9e291684180297f8a7932D22f598 src/CultureBotFactory.sol:CultureBotFactory
	@forge verify-contract --chain-id 84532 --watch --constructor-args `cast abi-encode "constructor(string,string ,uint256,address[3],uint256[3])" "$(NAME)" "$(SYMBOL)" "$(MAX_SUPPLY)" "[$(ALLOCATION_ADDY1),$(ALLOCATION_ADDY2),$(ALLOCATION_ADDY3)]" "[$(ALLOCATIONAMOUNT1),$(ALLOCATIONAMOUNT2),$(ALLOCATIONAMOUNT3)]" ` --etherscan-api-key $(ETHERSCAN_API_KEY) --compiler-version 0.8.24 0xF8Be09e111b1a5614F4E58A04511FaC5c81814e6 src/CultureBotTokenBoilerPlate.sol:CultureBotTokenBoilerPlate
	