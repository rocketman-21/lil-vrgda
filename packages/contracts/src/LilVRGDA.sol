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

    // How often the VRGDA price will update to reflect VRGDA pricing rules
    uint256 public immutable updateInterval = 15 minutes;

    // Time of sale of the first lilNoun, used to calculate VRGDA price
    uint256 public startTime;

    // The minimum price accepted in an auction
    uint256 public reservePrice;

    // The WETH contract address
    address public wethAddress;

    // The Nouns ERC721 token contract
    INounsToken public nounsToken;

    // The Nouns Seeder contract
    INounsSeeder public nounsSeeder;

    // The Nouns Descriptor contract
    INounsDescriptor public nounsDescriptor;

    // The manager who can initialize the contract
    address public immutable manager;

    ///                                            ///
    ///                   ERRORS                   ///
    ///                                            ///

    // Reverts when the caller is not the manager
    error NOT_MANAGER();

    // Reverts when the address is zero
    error ADDRESS_ZERO();

    ///                                            ///
    ///                CONSTRUCTOR                 ///
    ///                                            ///

    /**
     * @notice Creates a new LilVRGDA contract instance.
     * @dev Initializes the LinearVRGDA with pricing parameters and sets the manager.
     * @param _targetPrice The target price for a token if sold on pace, scaled by 1e18.
     * @param _priceDecayPercent The percent price decays per unit of time with no sales, scaled by 1e18.
     * @param _perTimeUnit The number of tokens to target selling in 1 full unit of time, scaled by 1e18.
     * @param _manager The address of the manager who can initialize the contract.
     */
    constructor(
        int256 _targetPrice,
        int256 _priceDecayPercent,
        int256 _perTimeUnit,
        address _manager
    ) LinearVRGDA(_targetPrice, _priceDecayPercent, _perTimeUnit) {
        if (_manager == address(0)) revert ADDRESS_ZERO();

        manager = _manager;
    }

    /**
     * @notice Initializes a token's metadata descriptor
     * @param _nounsTokenAddress The address of the token contract
     * @param _nounsSeederAddress The address of the seeder contract
     * @param _nounsDescriptorAddress The address of the descriptor contract
     * @param _wethAddress The address of the WETH contract
     * @param _reservePrice The reserve price for the auction
     * @param _nextNounId The next noun ID to be minted
     */
    function initialize(
        address _nounsTokenAddress,
        address _nounsSeederAddress,
        address _nounsDescriptorAddress,
        address _wethAddress,
        uint256 _reservePrice,
        uint256 _nextNounId
    ) external initializer {
        if (msg.sender != manager) revert NOT_MANAGER();
        if (_nounsTokenAddress == address(0)) revert ADDRESS_ZERO();
        if (_nounsSeederAddress == address(0)) revert ADDRESS_ZERO();
        if (_nounsDescriptorAddress == address(0)) revert ADDRESS_ZERO();
        if (_wethAddress == address(0)) revert ADDRESS_ZERO();

        // Setup ownable
        __Ownable_init(); // sets owner to msg.sender
        // Setup reentrancy guard
        __ReentrancyGuard_init();
        // Setup pausable
        __Pausable_init();

        nounsToken = INounsToken(_nounsTokenAddress);
        nounsSeeder = INounsSeeder(_nounsSeederAddress);
        nounsDescriptor = INounsDescriptor(_nounsDescriptorAddress);

        nextNounId = _nextNounId;

        // If we are upgrading, don't reset the start time
        if (startTime == 0) startTime = block.timestamp;

        wethAddress = _wethAddress;
        reservePrice = _reservePrice;
    }

    /**
     * @notice Allows a user to buy a Noun immediately at the current VRGDA price if conditions are met.
     * @param expectedNounId The expected ID of the Noun to be bought.
     * @param expectedParentBlockhash The expected parent blockhash to validate the transaction.
     * @dev This function is payable and requires the sent value to be at least the reserve price and the current VRGDA price.
     * It checks the expected parent blockhash and Noun ID for validity, mints the Noun, transfers it, handles refunds, and sends funds to the DAO.
     * It reverts if the conditions are not met or if the transaction is not valid according to VRGDA rules.
     */
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

        // Increment the next noun ID.
        nextNounId = mintedNounId + 1;

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

        emit AuctionSettled(mintedNounId, msg.sender, price);
    }

    /**
     * @notice Set the VRGDA reserve price.
     * @dev Only callable by the owner.
     */
    function setReservePrice(uint256 _reservePrice) external onlyOwner {
        reservePrice = _reservePrice;

        emit AuctionReservePriceUpdated(_reservePrice);
    }

    /**
     * @notice Pause the LilVRGDA auction.
     * @dev This function can only be called by the owner when the
     * contract is unpaused. No new Lils can be sold when paused.
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

    /**
     * @notice Fetches the next noun's details including ID, seed, SVG, price, and blockhash.
     * @dev Generates the seed and SVG for the next noun, calculates its price based on VRGDA rules, and fetches the blockhash.
     * @return nounId The ID of the next noun.
     * @return seed The seed data for generating the next noun's SVG.
     * @return svg The SVG image of the next noun.
     * @return price The price of the next noun according to VRGDA rules.
     * @return hash The blockhash associated with the next noun.
     */
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

    /**
     * @notice Calculates the current price of a VRGDA token based on the time elapsed and the next noun ID.
     * @dev This function computes the absolute time since the start of the auction, adjusts it to the nearest day, and then calculates the price using the VRGDA formula.
     * @return The current price of the next VRGDA token.
     */
    function getCurrentVRGDAPrice() public view returns (uint256) {
        uint256 absoluteTimeSinceStart = block.timestamp - startTime; // Calculate the absolute time since the auction started.
        return
            getVRGDAPrice(
                toDaysWadUnsafe(absoluteTimeSinceStart - (absoluteTimeSinceStart % updateInterval)), // Adjust time to the nearest day.
                nextNounId // The number sold
            );
    }

    /**
     * @notice Fetches the next noun ID that will be minted to the caller.
     * @dev Handles edge cases in the nouns token contract for founders rewards.
     * @return nounId The ID of the next noun.
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
     * @param _to The address to transfer ETH to.
     * @param _amount The amount of ETH to transfer.
     */
    function _safeTransferETHWithFallback(address _to, uint256 _amount) private {
        // Ensure the contract has enough ETH to transfer
        if (address(this).balance < _amount) revert("Insufficient balance");

        // Used to store if the transfer succeeded
        bool success;

        assembly {
            // Transfer ETH to the recipient
            // Limit the call to 30,000 gas
            success := call(30000, _to, _amount, 0, 0, 0, 0)
        }

        // If the transfer failed:
        if (!success) {
            // Wrap as WETH
            IWETH(wethAddress).deposit{ value: _amount }();

            // Transfer WETH instead
            bool wethSuccess = IWETH(wethAddress).transfer(_to, _amount);

            // Ensure successful transfer
            if (!wethSuccess) revert("WETH transfer failed");
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

    /**
     * @notice Ensures the caller is authorized to upgrade the contract to a new implementation.
     * @dev This function is invoked in the UUPS `upgradeTo` and `upgradeToAndCall` methods.
     * @param _impl Address of the new contract implementation.
     */
    function _authorizeUpgrade(address _impl) internal view override onlyOwner {}
}
