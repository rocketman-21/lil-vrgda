# lil-vrgda

VRGDA Contracts for [Lil Nouns DAO](https://lilnouns.wtf)

## LilVRGDA

The LilVRGDA contract implements a Variable Rate Gradual Dutch Auction (VRGDA) mechanism for minting and selling Lil Nouns NFTs. It uses a linear VRGDA to dynamically adjust token prices based on time elapsed and the number of tokens sold, aiming to maintain a target issuance rate.

### Key Functionality

- Token Minting: Users can mint Lil Nouns by calling buyNow(), paying the current VRGDA price.
- Dynamic Pricing: The contract calculates token prices using VRGDA logic, updating at set intervals.
- Nouns Integration: Interacts with Nouns Token, Seeder, and Descriptor contracts for minting and metadata generation.
- Admin Controls: Allows owner to adjust parameters like reserve price, update interval, and pool size.

The contract includes security features such as reentrancy protection and pausability, and uses the UUPS proxy pattern for upgradeability.

## NounsSeederV2 Functionality and Changes

### Overview

The NounsSeederV2 contract introduces a new method for generating pseudo-random seeds, incorporating the use of the ILilVRGDA interface to fetch the block number for seed generation. This enhances flexibility and control over the seed generation process, and allows us to accurately predict which Lil Noun will be purchased given the block number in the VRGDA. 

Here's the fixed formatting for the section:

### Key Features and Changes

1. ILilVRGDA Integration:
   - Introduced ILilVRGDA interface to fetch the block number.
   - Added a constructor to initialize ILilVRGDA.

2. Seed Generation:
   - Added generateSeedForBlock function to generate seeds using a specified block number.
   - generateSeed now calls generateSeedForBlock using the block number provided by ILilVRGDA.

3. Improved Flexibility:
   - Allows specifying the block number for seed generation, providing better control and flexibility.
   - Utilizes blockhash(blockNumber) for generating pseudo-randomness, similar to the original method but with an adjustable block number.
