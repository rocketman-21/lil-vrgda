// SPDX-License-Identifier: GPL-3.0

/// @title The NounsToken pseudo-random seed generator

/*********************************
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░█████████░░█████████░░░ *
 * ░░░░░░██░░░████░░██░░░████░░░ *
 * ░░██████░░░████████░░░████░░░ *
 * ░░██░░██░░░████░░██░░░████░░░ *
 * ░░██░░██░░░████░░██░░░████░░░ *
 * ░░░░░░█████████░░█████████░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 *********************************/

pragma solidity ^0.8.6;

import { INounsSeeder } from "./interfaces/INounsSeeder.sol";
import { INounsDescriptorMinimal } from "./interfaces/INounsDescriptorMinimal.sol";

contract NounsSeederV2 is INounsSeeder {
    /**
     * @notice Generate a pseudo-random Noun seed using the previous blockhash and noun ID, and block number.
     */
    function generateSeedWithBlock(
        uint256 nounsMinted,
        uint256 lilNounderRewardNouns,
        uint256 nounsDAORewardNouns,
        INounsDescriptorMinimal descriptor,
        uint256 blockNumber
    ) external view override returns (Seed memory) {
        uint256 pseudorandomness = uint256(
            keccak256(
                abi.encodePacked(
                    keccak256(abi.encodePacked(blockhash(blockNumber), nounsMinted)),
                    keccak256(abi.encodePacked(blockhash(blockNumber), lilNounderRewardNouns)),
                    keccak256(abi.encodePacked(blockhash(blockNumber), nounsDAORewardNouns))
                )
            )
        );

        uint256 backgroundCount = descriptor.backgroundCount();
        uint256 bodyCount = descriptor.bodyCount();
        uint256 accessoryCount = descriptor.accessoryCount();
        uint256 headCount = descriptor.headCount();
        uint256 glassesCount = descriptor.glassesCount();

        return
            Seed({
                background: uint48(uint48(pseudorandomness) % backgroundCount),
                body: uint48(uint48(pseudorandomness >> 48) % bodyCount),
                accessory: uint48(uint48(pseudorandomness >> 96) % accessoryCount),
                head: uint48(uint48(pseudorandomness >> 144) % headCount),
                glasses: uint48(uint48(pseudorandomness >> 192) % glassesCount)
            });
    }
}
