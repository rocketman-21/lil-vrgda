# Lil Nouns - Lil VRGDA Upgrade Audit Report

### Reviewed by: 0x52 ([@IAm0x52](https://twitter.com/IAm0x52))

### Review Date(s): 4/29/24 - 5/1/24

### Fix Review Date(s): 5/5/24 & 5/7/24

# 0x52 Background

As an independent smart contract auditor I have completed over 100 separate reviews. I primarily compete in public contests as well as conducting private reviews (like this one here). I have more than 30 1st place finishes (and counting) in public contests on [Code4rena](https://code4rena.com/@0x52) and [Sherlock](https://audits.sherlock.xyz/watson/0x52). I have also partnered with [SpearbitDAO](https://cantina.xyz/u/iam0x52) as a Lead Security researcher. My work has helped to secure over $1 billion in TVL across 100+ protocols.

# Scope

The [lil-vrgda](https://github.com/rocketman-21/lil-vrgda/tree/main) repo was reviewed at commit hash [d645415](https://github.com/rocketman-21/lil-vrgda/tree/d645415e5e69e21bafed7ed7b77e7ad50ea4732d)

In-Scope Contracts
- packages/contracts/src/LilVRGDA.sol
- packages/contracts/src/NounsSeederV2.sol

Deployment Chain(s)
- Ethereum Mainnet

# Summary of Findings

|  Identifier  | Title                        | Severity      | Mitigated |
| ------ | ---------------------------- | ------------- | ----- |
| [H-01] | [Incorrect require statement allows duplicate nouns to be created](#h-01-incorrect-require-statement-allows-duplicate-nouns-to-be-created) | HIGH | ✔️ |
| [H-02] | [LilVRGDA#getCurrentVRGDAPrice includes previously minted tokens leading to highly incorrect pricing](#h-02-lilvrgdagetcurrentvrgdaprice-includes-previously-minted-tokens-leading-to-highly-incorrect-pricing) | HIGH | ✔️ |
| [M-01] | [buyNow will mint token with incorrect metadata](#m-01-buynow-will-mint-token-with-incorrect-metadata) | MEDIUM | ✔️ |
| [M-02] | [Inclusion of nounId in NounsSeederV2#generateSeedWithBlock and generateSeed will cause all prospective noun traits to be scrambled after purchase](#m-02-inclusion-of-nounid-in-nounsseederv2generateseedwithblock-and-generateseed-will-cause-all-prospective-noun-traits-to-be-scrambled-after-purchase) | MEDIUM | ✔️ |

# Detailed Findings

## [H-01] Incorrect require statement allows duplicate nouns to be created

### Details 

[LilVRGDA.sol#L145-L150](https://github.com/rocketman-21/lil-vrgda/blob/d645415e5e69e21bafed7ed7b77e7ad50ea4732d/packages/contracts/src/LilVRGDA.sol#L145-L150)

    require(
        expectedBlockNumber <= block.number - 1 ||
            expectedBlockNumber > lastTokenBlock ||
            expectedBlockNumber >= block.number - poolSize,
        "Invalid block number"
    );

The check above is used to prevent block reuse for noun trait selection. It will pass if ANY of the conditions are true rather than enforcing that ALL conditions true. Due to the use of block.number in both the 1st and 3rd statement, this will allow ANY block to be used even if it has already been used. This allows duplicate nouns to be minted through seed collision.

### Lines of Code

[LilVRGDA.sol#L145-L150](https://github.com/rocketman-21/lil-vrgda/blob/d645415e5e69e21bafed7ed7b77e7ad50ea4732d/packages/contracts/src/LilVRGDA.sol#L145-L150)

### Recommendation

Switch all `||` to `&&`:

        require(
    -       expectedBlockNumber <= block.number - 1 ||
    -           expectedBlockNumber > lastTokenBlock ||
    +       expectedBlockNumber <= block.number - 1 &&
    +           expectedBlockNumber > lastTokenBlock &&
                expectedBlockNumber >= block.number - poolSize,
            "Invalid block number"
        );

### Remediation

Fixed as recommended in [PR#2](https://github.com/rocketman-21/lil-vrgda/pull/2/)

## [H-02] LilVRGDA#getCurrentVRGDAPrice includes previously minted tokens leading to highly incorrect pricing

### Details 

[LilVRGDA.sol#L286-L295](https://github.com/rocketman-21/lil-vrgda/blob/d645415e5e69e21bafed7ed7b77e7ad50ea4732d/packages/contracts/src/LilVRGDA.sol#L286-L295)

    function getCurrentVRGDAPrice() public view returns (uint256) {
        uint256 absoluteTimeSinceStart = block.timestamp - startTime; // Calculate the absolute time since the auction started.
        uint256 price = getVRGDAPrice(
            toDaysWadUnsafe(absoluteTimeSinceStart - (absoluteTimeSinceStart % updateInterval)), // Adjust time to the nearest day.
            nextNounId // The number sold
        );

        // return max of price and reservePrice
        return price > reservePrice ? price : reservePrice;
    }

When calculating the price, nextNounId is used to determine the number of nouns sold. The problem is this is inclusive of all nouns minted, including those minted under the previous auction house. With ~8000 nouns minted already, this will cause the price to be wildly inflated, overcharging buyers significantly

### Lines of Code

[LilVRGDA.sol#L286-L295](https://github.com/rocketman-21/lil-vrgda/blob/d645415e5e69e21bafed7ed7b77e7ad50ea4732d/packages/contracts/src/LilVRGDA.sol#L286-L295)

### Recommendation

Track the tokenId when the contract is initialized and use the difference between that and the current tokenId to determine the number of tokens minted by the new contract.

### Remediation

Fixes as recommended in [PR#3](https://github.com/rocketman-21/lil-vrgda/pull/3/). Additionally nounder token rewards were excluded in [PR#6](https://github.com/rocketman-21/lil-vrgda/pull/6/) and [PR#11](https://github.com/rocketman-21/lil-vrgda/pull/11/)

## [M-01] buyNow will mint token with incorrect metadata

### Details 

[LilVRGDA.sol#L164](https://github.com/rocketman-21/lil-vrgda/blob/d645415e5e69e21bafed7ed7b77e7ad50ea4732d/packages/contracts/src/LilVRGDA.sol#L164)

    uint256 mintedNounId = nounsToken.mint();

When minting nouns, LilVRGDA#buyNow calls NounsToken#mint. As seen above the expected block number is never passed as an argument.

[NounsToken.sol#L286-L293](https://github.com/rocketman-21/lil-vrgda/blob/d645415e5e69e21bafed7ed7b77e7ad50ea4732d/packages/contracts/src/NounsToken.sol#L286-L293)

    function _mintTo(address to, uint256 nounId) internal returns (uint256) {
        INounsSeeder.Seed memory seed = seeds[nounId] = seeder.generateSeed(nounId, descriptor);

        _mint(owner(), to, nounId);
        emit NounCreated(nounId, seed);

        return nounId;
    }

As a result, NounsToken will utilize NounsSeederV2#generateSeed when creating the metadata for the noun. This will result in the noun being minted using `block.number - 1` instead of `expectedBlockNumber`. This will result in an incorrect noun being minted.

### Lines of Code

[NounsToken.sol#L165-L175](https://github.com/rocketman-21/lil-vrgda/blob/d645415e5e69e21bafed7ed7b77e7ad50ea4732d/packages/contracts/src/NounsToken.sol#L165-L175)

### Recommendation

NounsToken is not upgradeable so an indirect fix is needed. LilVRGDA should set a public variable to the block number allowing seederV2 to read and mint based on that.

### Remediation

Fixed as recommended in [PR#11](https://github.com/rocketman-21/lil-vrgda/pull/11/)


## [M-02] Inclusion of nounId in NounsSeederV2#generateSeedWithBlock and generateSeed will cause all prospective noun traits to be scrambled after purchase

### Details 

[NounsSeederV2.sol#L29](https://github.com/rocketman-21/lil-vrgda/blob/d645415e5e69e21bafed7ed7b77e7ad50ea4732d/packages/contracts/src/NounsSeederV2.sol#L29)

    uint256 pseudorandomness = uint256(keccak256(abi.encodePacked(blockhash(blockNumber), nounId)));

The hash of nounId is used to determine pseudorandomness.

[NounsSeederV2.sol#L38-L54](https://github.com/rocketman-21/lil-vrgda/blob/d645415e5e69e21bafed7ed7b77e7ad50ea4732d/packages/contracts/src/NounsSeederV2.sol#L38-L54)

    return Seed({
        background: uint48(
            uint48(pseudorandomness) % backgroundCount
        ),
        body: uint48(
            uint48(pseudorandomness >> 48) % bodyCount
        ),
        accessory: uint48(
            uint48(pseudorandomness >> 96) % accessoryCount
        ),
        head: uint48(
            uint48(pseudorandomness >> 144) % headCount
        ),
        glasses: uint48(
            uint48(pseudorandomness >> 192) % glassesCount
        )
    });

pseudorandomness is in turn used to determine the traits of the noun. After a noun is purchased, the nounId will be incremented. This will cause the traits of all prospective nouns to be randomized again. If two users buy nouns close to each other, the second transaction to be processed will yield a noun that is completely different from the one being requested. This can occur accidentally or maliciously as an attempt to grief other users.

### Lines of Code

[NounsSeederV2.sol#L28-L55](https://github.com/rocketman-21/lil-vrgda/blob/d645415e5e69e21bafed7ed7b77e7ad50ea4732d/packages/contracts/src/NounsSeederV2.sol#L28-L55)

### Recommendation

There are two solutions to this.

Simple - Add an expectedNounId argument to LilVRGDA#buyNow. If the minted nounId is does match the expected, the transaction should revert. The downside to this is that the second user's gas will be wasted and their desired noun will lost

Recommended - Get rid of the nounID completely from seed generation and replacing it with a domain separator. Implement 3 separate domains: 

1. Nouns minted by LilVRGDA
2. Nouns xxx0
3. Nouns xxx1

This will prevent noun traits being re-randomized, while preventing any collisions from occurring **as long as domains are sufficiently long**

### Remediation

Fixed using the simple recommendation in [PR#7](https://github.com/rocketman-21/lil-vrgda/pull/7/)