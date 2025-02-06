// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IBuzzTokenFactory} from "./interfaces/IBuzzTokenFactory.sol";

/**
 * @title HighlightsManager
 * @notice This contract manages the highlighting of tokens
 * @author nexusflip, 0xMitzie
 */
contract HighlightsManager is Ownable, Pausable {
    /// @notice Event emitted when a token is highlighted
    event TokenHighlighted(
        address indexed token,
        address indexed buyer,
        uint256 duration,
        uint256 bookedUntil,
        uint256 fee
    );
    /// @notice Event emitted when the treasury address is set
    event TreasurySet(address indexed treasury);
    /// @notice Event emitted when the base fee is set
    event BaseFeeSet(uint256 baseFeePerSecond);
    /// @notice Event emitted when the hard cap is set
    event HardCapSet(uint256 hardCap);
    /// @notice Event emitted when the cool down period is set
    event CoolDownPeriodSet(uint256 coolDownPeriod);

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
    error HighlightsManager_TreasuryAddressZero();
    /// @notice Error thrown when the transfer in native currency fails
    error HighlightsManager_BeraTransferFailed();
    /// @notice Error thrown when the slot is already occupied
    error HighlightsManager_SlotOccupied();
    /// @notice Error thrown when the token is within the cool down period
    error HighlightsManager_TokenWithinCoolDown();
    /// @notice Error thrown when the token has not been deployed through the factory
    error HighlightsManager_NotFromTokenFactory();

    /// @notice The interface for the BuzzTokenFactory
    IBuzzTokenFactory public tokenFactory;

    /// @notice The minimum duration allowed in seconds
    uint256 public constant MIN_DURATION = 60; // 60 = 1 minute
    /// @notice The threshold after which the fee increases exponentially
    uint256 public constant EXP_THRESHOLD = 600; // 600 = 10 minutes
    /// @notice Growth rate for 25x fee on 1 hour vs 10 minutes
    uint256 public constant GROWTH_FACTOR = 49;
    /// @notice The maximum duration allowed in seconds
    uint256 public hardCap;
    /// @notice The cool down period for a token in seconds
    uint256 public coolDownPeriod;
    /// @notice The base fee per second to charge in wei
    uint256 public baseFeePerSecond;
    /// @notice The timestamp when the latest highlight expires
    uint256 public bookedUntil;
    /// @notice The treasury address where fees are sent
    address payable public treasury;

    /// @notice The timestamp when a token can be highlighted again
    mapping(address => uint256) public tokenCoolDownUntil;

    /**
     * @notice Constructor
     * @param _treasury The treasury address where fees are sent
     * @param _tokenFactory The address of the token factory
     * @param _hardCap The maximum duration allowed in seconds
     * @param _baseFeePerSecond The base fee per second to charge in wei
     * @param _coolDownPeriod The cool down period for a token in seconds
     */
    constructor(
        address payable _treasury,
        address _tokenFactory,
        uint256 _hardCap,
        uint256 _baseFeePerSecond,
        uint256 _coolDownPeriod
    ) {
        if (_hardCap < MIN_DURATION)
            revert HighlightsManager_HardCapBelowMinimumDuration();

        treasury = _treasury;
        tokenFactory = IBuzzTokenFactory(_tokenFactory);
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
     * @dev BookedUntil must be in the past to allow a new highlight.
     * @param token The address of the token to highlight
     * @param duration The duration in seconds
     */
    function highlightToken(
        address token,
        uint256 duration
    ) external payable whenNotPaused {
        if (bookedUntil > block.timestamp)
            revert HighlightsManager_SlotOccupied();
        if (tokenCoolDownUntil[token] > block.timestamp)
            revert HighlightsManager_TokenWithinCoolDown();
        if (!tokenFactory.isDeployed(token))
            revert HighlightsManager_NotFromTokenFactory();

        bool success;
        uint256 fee = quote(duration);
        if (msg.value < fee) revert HighlightsManager_InsufficientFee();

        bookedUntil = block.timestamp + duration;
        tokenCoolDownUntil[token] = block.timestamp + coolDownPeriod;

        (success, ) = treasury.call{value: fee}("");
        if (!success) revert HighlightsManager_BeraTransferFailed();

        if (msg.value > fee) {
            (success, ) = msg.sender.call{value: msg.value - fee}("");
            if (!success) revert HighlightsManager_BeraTransferFailed();
        }

        emit TokenHighlighted(token, msg.sender, duration, bookedUntil, fee);
    }

    /**
     * @notice Sets the treasury address
     * @dev Only the owner can call this function
     * @param treasury_ The treasury address where fees are sent
     */
    function setTreasury(address payable treasury_) external onlyOwner {
        if (treasury_ == address(0))
            revert HighlightsManager_TreasuryAddressZero();

        treasury = treasury_;
        emit TreasurySet(treasury_);
    }

    /**
     * @notice Sets the hard cap for the duration
     * @dev Only the owner can call this function
     * @param hardCap_ The maximum duration allowed in seconds
     */
    function setHardCap(uint256 hardCap_) external onlyOwner {
        if (hardCap_ < MIN_DURATION)
            revert HighlightsManager_HardCapBelowMinimumDuration();

        hardCap = hardCap_;
        emit HardCapSet(hardCap_);
    }

    /**
     * @notice Sets the base fee per second
     * @dev Only the owner can call this function
     * @param baseFeePerSecond_ The base fee per second to charge in wei
     */
    function setBaseFee(uint256 baseFeePerSecond_) external onlyOwner {
        baseFeePerSecond = baseFeePerSecond_;
        emit BaseFeeSet(baseFeePerSecond_);
    }

    /**
     * @notice Sets the cool down period for a token
     * @dev Only the owner can call this function
     * @param coolDownPeriod_ The cool down period in seconds
     */
    function setCoolDownPeriod(uint256 coolDownPeriod_) external onlyOwner {
        coolDownPeriod = coolDownPeriod_;
        emit CoolDownPeriodSet(coolDownPeriod_);
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

    /**
     * @notice Quotes the fee for highlighting a token for a given duration
     * @param duration The duration in seconds
     * @return fee The fee in wei
     */
    function quote(uint256 duration) public view returns (uint256 fee) {
        uint256 expThreshold = EXP_THRESHOLD;
        uint256 baseFeePs = baseFeePerSecond;

        if (duration == 0) revert HighlightsManager_ZeroDuration();
        if (duration < MIN_DURATION)
            revert HighlightsManager_DurationBelowMinimum();
        if (duration > hardCap)
            revert HighlightsManager_DurationExceedsHardCap();
        if (duration <= expThreshold) {
            fee = baseFeePs * duration;
        } else {
            uint256 extraTime = duration - expThreshold;

            // Calculate exponential fee using the growth factor
            uint256 exponentialFee = (baseFeePs * extraTime * GROWTH_FACTOR) /
                10;

            // Total fee is the sum of the base fee and the exponential component
            fee = (baseFeePs * expThreshold) + exponentialFee;
        }
        return fee;
    }
}
