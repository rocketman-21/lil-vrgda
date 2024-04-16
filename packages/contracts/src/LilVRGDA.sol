// SPDX-License-Identifier: GPL-3.0

/// @title The Lil Nouns DAO VRGDA

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

pragma solidity ^0.8.22;

import { LinearVRGDA } from "./vrgda/LinearVRGDA.sol";

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { UUPS } from "./proxy/UUPS.sol";

import { toDaysWadUnsafe } from "solmate/src/utils/SignedWadMath.sol";
import { INounsSeeder } from "./interfaces/INounsSeeder.sol";
import { INounsToken } from "./interfaces/INounsToken.sol";
import { INounsDescriptor } from "./interfaces/INounsDescriptor.sol";
import { ILilVRGDA } from "./interfaces/ILilVRGDA.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LilVRGDA is ILilVRGDA, LinearVRGDA, PausableUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPS {
    // The very next nounID that will be minted on auction,
    // equal to total number sold + 1
    uint256 public nextNounId;

    // Time of sale of the first lilNoun, used to calculate VRGDA price
    uint256 public immutable startTime;

    // How often the VRGDA price will update to reflect VRGDA pricing rules
    uint256 public immutable updateInterval = 15 minutes;

    // The minimum price accepted in an auction
    uint256 public reservePrice;

    // The WETH contract address
    address public immutable wethAddress;

    // The Nouns ERC721 token contract
    INounsToken public immutable nounsToken;

    // The Nouns Seeder contract
    INounsSeeder public immutable nounsSeeder;

    // The Nouns Descriptor contract
    INounsDescriptor public immutable nounsDescriptor;

    constructor(
        int256 _targetPrice,
        int256 _priceDecayPercent,
        int256 _perTimeUnit,
        uint256 _nextNounId,
        uint256 _startTime,
        address _nounsTokenAddress,
        address _nounsSeederAddress,
        address _nounsDescriptorAddress,
        address _wethAddress,
        uint256 _reservePrice
    ) LinearVRGDA(_targetPrice, _priceDecayPercent, _perTimeUnit) {
        nounsToken = INounsToken(_nounsTokenAddress);
        nounsSeeder = INounsSeeder(_nounsSeederAddress);
        nounsDescriptor = INounsDescriptor(_nounsDescriptorAddress);
        nextNounId = _nextNounId;
        startTime = _startTime;
        wethAddress = _wethAddress;
        reservePrice = _reservePrice;
    }

    function buyNow(
        uint256 expectedNounId,
        bytes32 expectedParentBlockhash
    ) external payable override whenNotPaused nonReentrant {
        // Only settle if desired Noun would be minted
        bytes32 parentBlockhash = blockhash(block.number - 1);
        require(expectedParentBlockhash == parentBlockhash, "Invalid or expired blockhash");
        uint256 _nextNounIdForCaller = nextNounIdForCaller();
        require(expectedNounId == _nextNounIdForCaller, "Invalid or expired nounId");
        require(msg.value >= reservePrice, "Below reservePrice");

        // Validate the purchase request against the VRGDA rules.
        uint256 price = getCurrentVRGDAPrice();
        require(msg.value >= price, "Insufficient funds");

        // Call settleAuction on the nouns contract.
        uint256 mintedNounId = nounsToken.mint();
        assert(mintedNounId == _nextNounIdForCaller);

        // Sends token to caller.
        nounsToken.transferFrom(address(this), msg.sender, mintedNounId);

        // Sends the funds to the DAO.
        if (msg.value > 0) {
            uint256 refundAmount = msg.value - price;
            if (refundAmount > 0) {
                _safeTransferETHWithFallback(msg.sender, refundAmount);
            }
            if (price > 0) {
                _safeTransferETHWithFallback(owner(), price);
            }
        }

        nextNounId = mintedNounId + 1;
        emit AuctionSettled(mintedNounId, msg.sender, price);
    }

    /**
     * @notice Set the auction reserve price.
     * @dev Only callable by the owner.
     */
    function setReservePrice(uint256 _reservePrice) external onlyOwner {
        reservePrice = _reservePrice;

        emit AuctionReservePriceUpdated(_reservePrice);
    }

    /**
     * @notice Pause the LilVRGDA auction.
     * @dev This function can only be called by the owner when the
     * contract is unpaused. No new auctions can be started when paused.
     */
    function pause() external override onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the LilVRGDA auction.
     * @dev This function can only be called by the owner when the
     * contract is paused.
     */
    function unpause() external override onlyOwner {
        _unpause();
    }

    function fetchNextNoun()
        external
        view
        override
        returns (uint256 nounId, INounsSeeder.Seed memory seed, string memory svg, uint256 price, bytes32 hash)
    {
        uint256 _nextNounIdForCaller = nextNounIdForCaller();
        // Generate the seed for the next noun.
        seed = nounsSeeder.generateSeed(_nextNounIdForCaller, nounsDescriptor);

        // Generate the SVG from seed using the descriptor.
        svg = nounsDescriptor.generateSVGImage(seed);

        // Calculate price based on VRGDA rules.
        price = getCurrentVRGDAPrice();

        // Fetch the blockhash associated with this noun.
        hash = blockhash(block.number - 1);

        return (_nextNounIdForCaller, seed, svg, price, hash);
    }

    // TODO: I can keep this function private and still test by having my
    // tests inherit from this contract
    function getCurrentVRGDAPrice() public view returns (uint256) {
        uint256 absoluteTimeSinceStart = block.timestamp - startTime;
        return
            getVRGDAPrice(
                toDaysWadUnsafe(absoluteTimeSinceStart - (absoluteTimeSinceStart % updateInterval)),
                nextNounId
            );
    }

    /**
     * @dev handles edge case in nouns token contract
     */
    function nextNounIdForCaller() public view returns (uint256) {
        // Calculate nounId that would be minted to the caller
        uint256 _nextNounIdForCaller = nextNounId;
        if (_nextNounIdForCaller <= 175300 && _nextNounIdForCaller % 10 == 0) {
            _nextNounIdForCaller++;
        }
        if (_nextNounIdForCaller <= 175301 && _nextNounIdForCaller % 10 == 1) {
            _nextNounIdForCaller++;
        }
        return _nextNounIdForCaller;
    }

    /**
     * @notice Transfer ETH. If the ETH transfer fails, wrap the ETH and try send it as wethAddress.
     */
    function _safeTransferETHWithFallback(address to, uint256 amount) internal {
        if (!_safeTransferETH(to, amount)) {
            IWETH(wethAddress).deposit{ value: amount }();
            IERC20(wethAddress).transfer(to, amount);
        }
    }

    /**
     * @notice Transfer ETH and return the success status.
     * @dev This function only forwards 30,000 gas to the callee.
     */
    function _safeTransferETH(address to, uint256 value) internal returns (bool) {
        (bool success, ) = to.call{ value: value, gas: 30_000 }(new bytes(0));
        return success;
    }

    /// @notice Ensures the caller is authorized to upgrade the contract to a new implementation
    /// @dev This function is called in UUPS `upgradeTo` & `upgradeToAndCall`
    /// @param _impl The address of the new implementation
    function _authorizeUpgrade(address _impl) internal view override onlyOwner {}
}
