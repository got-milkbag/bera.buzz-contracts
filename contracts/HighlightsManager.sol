// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";

contract HighlightsManager is Ownable, ReentrancyGuard {
    /// @notice Error thrown when the duration is zero
    error HighlightsManager_ZeroDuration();
    /// @notice Error thrown when the duration is above the hard cap
    error HighlightsManager_DurationExceedsHardCap();
    /// @notice Error thrown when the duration is below the MIN_DURATION
    error HighlightsManager_DurationBelowMinimum();
    /// @notice Error thrown when the fee is insufficient
    error HighlightsManager_InsufficientFee();
    /// @notice Error thrown when the hard cap is below the MIN_DURATION
    error HighlightsManager_HardCapBelowMinimumDuration();
    /// @notice Error thrown when the treasury is the zero address
    error HighlightsManager_TreasuryZeroAddress();
    /// @notice Error thrown when the transfer in native currency fails
    error HighlightsManager_EthTransferFailed();

    /// @notice Event emitted when a token is highlighted
    event TokenHighlighted(address indexed token, address indexed buyer, uint256 startAt, uint256 duration, uint256 bookedUntil);
    /// @notice Event emitted when the treasury address is set
    event TreasurySet(address indexed treasury);
    /// @notice Event emitted when the base fee is set
    event BaseFeeSet(uint256 baseFeePerSecond);
    /// @notice Event emitted when the hard cap is set
    event HardCapSet(uint256 hardCap);

    /// @notice The minimum duration allowed in seconds
    uint256 public constant MIN_DURATION = 60; // 60 = 1 minute
    /// @notice The threshold after which the fee increases exponentially
    uint256 public constant EXP_THRESHOLD = 600; // 600 = 10 minutes
    /// @notice The maximum duration allowed in seconds
    uint256 public hardCap;
    /// @notice The base fee per second to charge in wei
    uint256 public baseFeePerSecond;
    /// @notice The treasury address where fees are sent
    address payable public treasury;
    /// @notice The timestamp when the latest highlight expires
    uint256 public bookedUntil;

    /**
     * @notice Constructor
     * @param _treasury The treasury address where fees are sent
     * @param _hardCap The maximum duration allowed in seconds
     * @param _baseFeePerSecond The base fee per second to charge in wei
     */
    constructor(address payable _treasury, uint256 _hardCap, uint256 _baseFeePerSecond) {
        if (_hardCap < MIN_DURATION) revert HighlightsManager_HardCapBelowMinimumDuration();
        if (_treasury == address(0)) revert HighlightsManager_TreasuryZeroAddress();

        treasury = _treasury;
        hardCap = _hardCap;
        baseFeePerSecond = _baseFeePerSecond;

        emit TreasurySet(_treasury);
        emit HardCapSet(_hardCap);
        emit BaseFeeSet(_baseFeePerSecond);
    }

    /**
     * @notice Allows msg.sender to highlights a token for a given duration, paying the fee in native currency
     * @param token The address of the token to highlight
     * @param duration The duration in seconds
     */
    function highlightToken(address token, uint256 duration) external payable nonReentrant {
        uint256 fee = quote(duration);
        if (msg.value != fee) revert HighlightsManager_InsufficientFee();
        uint256 startAt;
        if (bookedUntil > block.timestamp) {
            startAt = bookedUntil + 1;
            bookedUntil += duration;
        } else {
            startAt = block.timestamp;
            bookedUntil = block.timestamp + duration;
        }

        (bool success, ) = treasury.call{value: fee}("");
        if (!success) revert HighlightsManager_EthTransferFailed();

        emit TokenHighlighted(token, msg.sender, startAt, duration, bookedUntil);
    }

    /**
     * @notice Quotes the fee for highlighting a token for a given duration
     * @param duration The duration in seconds
     * @return fee The fee in wei
     */
    function quote(uint256 duration) public view returns (uint256 fee) {
        if (duration == 0) revert HighlightsManager_ZeroDuration();
        if (duration < MIN_DURATION) revert HighlightsManager_DurationBelowMinimum();
        if (duration > hardCap) revert HighlightsManager_DurationExceedsHardCap();
        if (duration <= EXP_THRESHOLD) {
            fee = baseFeePerSecond * duration;
        } else {
            UD60x18 extraTime = ud(duration - EXP_THRESHOLD);
            UD60x18 maxExtraTime = ud(hardCap - EXP_THRESHOLD);
            UD60x18 baseFeePerSecondUd = ud(baseFeePerSecond);
            UD60x18 expThresholdUd = ud(EXP_THRESHOLD);
            UD60x18 wadUd = ud(1e18);
            UD60x18 logMultiplier = ud(50).log2(); // Fixed-point arithmetic for precision (change ud(50) to final multiplier on hour end)

            // Compute scaling factor T
            UD60x18 T = maxExtraTime.mul(wadUd).div(logMultiplier);

            // Calculate exponential growth component
            UD60x18 exponentialGrowth = (extraTime.mul(wadUd).div(T)).exp2().div(wadUd); // Adjusted for fixed-point
            UD60x18 exponentialFee = baseFeePerSecondUd.mul(extraTime).mul(exponentialGrowth);

            // Total fee is the sum of the base fee and the exponential component
            fee = ((baseFeePerSecondUd.mul(expThresholdUd)).add(exponentialFee)).unwrap();
        }
        return fee;
    }

    /**
     * @notice Sets the treasury address
     * @dev Only the owner can call this function
     * @param _treasury The treasury address where fees are sent
     */
    function setTreasury(address payable _treasury) external onlyOwner {
        if (_treasury == address(0)) revert HighlightsManager_TreasuryZeroAddress();
        treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    /**
     * @notice Sets the hard cap for the duration
     * @dev Only the owner can call this function
     * @param _hardCap The maximum duration allowed in seconds
     */
    function setHardCap(uint256 _hardCap) external onlyOwner {
        // require(_hardCap >= MIN_DURATION, "Hard cap must be >= minTime");
        if (_hardCap < MIN_DURATION) revert HighlightsManager_HardCapBelowMinimumDuration();
        hardCap = _hardCap;
        emit HardCapSet(_hardCap);
    }

    /**
     * @notice Sets the base fee per second
     * @dev Only the owner can call this function
     * @param _baseFeePerSecond The base fee per second to charge in wei
     */
    function setBaseFee(uint256 _baseFeePerSecond) external onlyOwner {
        baseFeePerSecond = _baseFeePerSecond;
        emit BaseFeeSet(_baseFeePerSecond);
    }
}
