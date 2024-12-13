// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract HighlightsManager is Ownable, Pausable, ReentrancyGuard {
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
    /// @notice Error thrown when the slot is already occupied
    error HighlightsManager_SlotOccupied();
    /// @notice Error thrown when the token is within the cool down period
    error HighlightsManager_TokenWithinCoolDown();

    /// @notice Event emitted when a token is highlighted
    event TokenHighlighted(address indexed token, address indexed buyer, uint256 duration, uint256 bookedUntil, uint256 fee);
    /// @notice Event emitted when the treasury address is set
    event TreasurySet(address indexed treasury);
    /// @notice Event emitted when the base fee is set
    event BaseFeeSet(uint256 baseFeePerSecond);
    /// @notice Event emitted when the hard cap is set
    event HardCapSet(uint256 hardCap);
    /// @notice Event emitted when the cool down period is set
    event CoolDownPeriodSet(uint256 coolDownPeriod);

    /// @notice The minimum duration allowed in seconds
    uint256 public constant MIN_DURATION = 60; // 60 = 1 minute
    /// @notice The threshold after which the fee increases exponentially
    uint256 public constant EXP_THRESHOLD = 600; // 600 = 10 minutes
    /// @notice The maximum duration allowed in seconds
    uint256 public hardCap;
    /// @notice The cool down period for a token in seconds
    uint256 public coolDownPeriod;
    /// @notice The base fee per second to charge in wei
    uint256 public baseFeePerSecond;
    /// @notice The treasury address where fees are sent
    address payable public treasury;
    /// @notice The timestamp when the latest highlight expires
    uint256 public bookedUntil;

    mapping(address => uint256) public tokenCoolDownUntil;

    /**
     * @notice Constructor
     * @param _treasury The treasury address where fees are sent
     * @param _hardCap The maximum duration allowed in seconds
     * @param _baseFeePerSecond The base fee per second to charge in wei
     */
    constructor(address payable _treasury, uint256 _hardCap, uint256 _baseFeePerSecond, uint256 _coolDownPeriod) {
        if (_hardCap < MIN_DURATION) revert HighlightsManager_HardCapBelowMinimumDuration();
        if (_treasury == address(0)) revert HighlightsManager_TreasuryZeroAddress();

        treasury = _treasury;
        hardCap = _hardCap;
        baseFeePerSecond = _baseFeePerSecond;
        coolDownPeriod = _coolDownPeriod;

        emit TreasurySet(_treasury);
        emit HardCapSet(_hardCap);
        emit BaseFeeSet(_baseFeePerSecond);
        emit CoolDownPeriodSet(_coolDownPeriod);
    }

    /**
     * @notice Allows msg.sender to highlights a token for a given duration, paying the fee in native currency
     * @notice BookedUntil must be in the past to allow a new highlight. quote() should be called beforehand to get the msg.value required.
     * @param token The address of the token to highlight
     * @param duration The duration in seconds
     */
    function highlightToken(address token, uint256 duration) external payable whenNotPaused nonReentrant {
        if (bookedUntil > block.timestamp) revert HighlightsManager_SlotOccupied();
        if (tokenCoolDownUntil[token] > block.timestamp) revert HighlightsManager_TokenWithinCoolDown();

        uint256 fee = quote(duration);
        if (msg.value != fee) revert HighlightsManager_InsufficientFee();

        bookedUntil = block.timestamp + duration;
        tokenCoolDownUntil[token] = block.timestamp + coolDownPeriod;
        (bool success, ) = treasury.call{value: fee}("");
        if (!success) revert HighlightsManager_EthTransferFailed();

        emit TokenHighlighted(token, msg.sender, duration, bookedUntil, fee);
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
            uint256 extraTime = duration - EXP_THRESHOLD;

            // Fixed growth factor G
            uint256 growthFactor = 98; // Representing 9.8 as an integer (fixed-point, scaled by 10) -> growth rate for 50x fee on 1 hour vs 10 minutes

            // Calculate exponential fee using the growth factor
            uint256 exponentialFee = (baseFeePerSecond * extraTime * growthFactor) / 10;

            // Total fee is the sum of the base fee and the exponential component
            fee = (baseFeePerSecond * EXP_THRESHOLD) + exponentialFee;
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

    function setCoolDownPeriod(uint256 _coolDownPeriod) external onlyOwner {
        coolDownPeriod = _coolDownPeriod;
        emit CoolDownPeriodSet(_coolDownPeriod);
    }

    /**
     * @notice Pauses the contract
     * @dev Only the owner can call this function.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     * @dev Only the owner can call this function.
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
