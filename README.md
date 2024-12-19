# CultureBot Protocol

A decentralized protocol for community-driven token launches utilizing exponential bonding curves and automated liquidity provisioning.

## Overview

CultureBot Protocol enables communities to launch their own tokens with built-in liquidity through an exponential bonding curve mechanism. The protocol automatically handles token minting, price discovery, and Uniswap V3 liquidity provision.

## Architecture

The protocol consists of three main components:

1. Factory Contract

   - Handles deployment of new token contracts
   - Manages initial supply allocation
   - Creates bonding curve contracts

2. Token Contract

   - ERC20 implementation
   - Handles token minting and transfers

3. Bonding Curve Contract

   - Implements exponential bonding curve
   - Manages token price discovery
   - Handles Uniswap V3 liquidity provision
   - Manages supply distribution

## Features

- Exponential bonding curve for price discovery
- Dynamic scaling factor for price stability
- Automatic Uniswap V3 liquidity provision
- Chainlink price feed integration
- PRBMath implementation for precise calculations
- Customizable initial token distribution
- Graduation mechanism for mature tokens

## Technical Specifications

### Token Distribution

- Maximum Supply: 100,000,000,000 tokens
- Initial Supply: 10% of maximum supply
- Bonding Curve Supply: 54% of maximum supply
- Liquidity Pool Allocation: 13.5% of maximum supply

### Bonding Curve Parameters

- Initial Price: 0.000000000024269 ETH
- Growth Rate (k): 69,420
- Graduation Market Cap: 69,420 USD
- Graduation ETH Amount: 24 ETH
