// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IReferralManager} from "./interfaces/IReferralManager.sol";

/**
 * @title ReferralManager
 * @notice This contract manages the referral system for the protocol
 * @author nexusflip, Zacharias Mitzelos
 */
contract ReferralManager is
    Ownable,
    Pausable,
    ReentrancyGuard,
    IReferralManager
{
    using SafeERC20 for IERC20;

    /// @notice Event emitted when a referral is set
    event ReferralSet(address indexed referrer, address indexed referredUser);
    /// @notice Event emitted when an indirect referral is set
    event IndirectReferralSet(
        address indexed indirectReferrer,
        address indexed referredUser,
        address indexed directReferrer
    );
    /// @notice Event emitted when a referral reward is received
    event ReferralRewardReceived(
        address indexed referrer,
        address indexed token,
        uint256 reward,
        bool isDirect
    );
    /// @notice Event emitted when a referral reward is paid out
    event ReferralPaidOut(
        address indexed referrer,
        address indexed token,
        uint256 reward
    );
    /// @notice Event emitted when the direct referral fee is set
    event DirectRefFeeBpsSet(uint256 directRefFeeBps);
    /// @notice Event emitted when the indirect referral fee is set
    event IndirectRefFeeBpsSet(uint256 indirectRefFeeBps);
    /// @notice Event emitted when the referral deadline is set
    event ReferralDeadlineSet(uint256 validUntil);
    /// @notice Event emitted when the payout threshold is set
    event PayoutThresholdSet(address token, uint256 payoutThreshold);
    /// @notice Event emitted when a vault is whitelisted
    event WhitelistedVaultSet(address indexed vault, bool status);

    /// @notice Error emitted when the caller is not authorized
    error ReferralManager_Unauthorised();
    /// @notice Error emitted when the payout is zero
    error ReferralManager_ZeroPayout();
    /// @notice Error emitted when the address is zero
    error ReferralManager_AddressZero();
    /// @notice Error emitted when the referral has expired
    error ReferralManager_ReferralExpired();
    /// @notice Error emitted when the referral has expired
    error ReferralManager_RewardTransferFailed();
    /// @notice Error emitted when the payout is below the threshold
    error ReferralManager_PayoutBelowThreshold();
    /// @notice Error emitted when the array lengths do not match
    error ReferralManager_ArrayLengthMismatch();

    /// @notice The maximum fee basis points
    uint256 public constant MAX_FEE_BPS = 10000;
    /// @notice The direct referral fee in basis points
    uint256 public directRefFeeBps; // eg 100 -> 1%
    /// @notice The indirect referral fee in basis points
    uint256 public indirectRefFeeBps; // eg 100 -> 1%
    /// @notice The referral deadline
    uint256 public validUntil;

    /// @notice Mapping for referred users and respective referrers
    mapping(address => address) public referredBy;
    /// @notice Mapping for indirect referrals
    mapping(address => address) public indirectReferral;
    /// @notice Whether a given vault is whitelisted
    mapping(address => bool) public whitelistedVault;
    /// @notice The payout threshold for a token
    mapping(address => uint256) public payoutThreshold;
    /// @notice Mapping for referrer balances
    mapping(address => mapping(address => uint256)) private _referrerBalances;

    /// @notice Fee bps is the % of the protocol fee that the referrer will receive
    constructor(
        uint256 _directRefFeeBps,
        uint256 _indirectRefFeeBps,
        uint256 _validUntil,
        address[] memory tokens,
        uint256[] memory _payoutThresholds
    ) {
        directRefFeeBps = _directRefFeeBps;
        indirectRefFeeBps = _indirectRefFeeBps;
        validUntil = _validUntil;

        if (tokens.length > 0) {
            if (tokens.length != _payoutThresholds.length)
                revert ReferralManager_ArrayLengthMismatch();

            for (uint256 i = 0; i < tokens.length; ) {
                payoutThreshold[tokens[i]] = _payoutThresholds[i];
                emit PayoutThresholdSet(tokens[i], _payoutThresholds[i]);

                unchecked {
                    ++i;
                }
            }
        }

        emit DirectRefFeeBpsSet(_directRefFeeBps);
        emit IndirectRefFeeBpsSet(_indirectRefFeeBps);
        emit ReferralDeadlineSet(_validUntil);
    }

    // Vault functions

    /// @notice Callable by the vault with the address of the referred user
    function receiveReferral(
        address user,
        address token,
        uint256 amount
    ) external nonReentrant {
        if (!whitelistedVault[msg.sender])
            revert ReferralManager_Unauthorised();
        address referrer = referredBy[user];

        if (validUntil < block.timestamp)
            revert ReferralManager_ReferralExpired();
        if (referrer == address(0)) revert ReferralManager_AddressZero();
        if (amount == 0) revert ReferralManager_ZeroPayout();

        if (indirectReferral[user] != address(0)) {
            // If there is an indirect referral
            uint256 indirectReferralAmount = (amount * indirectRefFeeBps) /
                MAX_FEE_BPS;
            _referrerBalances[indirectReferral[user]][
                token
            ] += indirectReferralAmount;
            emit ReferralRewardReceived(
                indirectReferral[user],
                token,
                indirectReferralAmount,
                false
            );

            uint256 directReferralAmount = amount - indirectReferralAmount;
            _referrerBalances[referrer][token] += directReferralAmount;
            emit ReferralRewardReceived(
                referrer,
                token,
                directReferralAmount,
                true
            );
        } else {
            _referrerBalances[referrer][token] += amount;
            emit ReferralRewardReceived(referrer, token, amount, true);
        }

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Callable by the vault to set the referral for a user
     * @param referrer The address of the referrer
     * @param user The address of the referred user
     */
    function setReferral(address referrer, address user) external nonReentrant {
        if (!whitelistedVault[msg.sender])
            revert ReferralManager_Unauthorised();

        if (
            (referredBy[user] != address(0)) ||
            (referrer == user) ||
            (referrer == address(0))
        ) {
            return;
        }

        referredBy[user] = referrer;
        emit ReferralSet(referrer, user);

        address indirectReferrer = referredBy[referrer];
        if (indirectReferrer != address(0)) {
            indirectReferral[user] = indirectReferrer;
            emit IndirectReferralSet(indirectReferrer, user, referrer);
        }
    }

    /**
     * @notice Calculates the referral fee for a user
     * @param user The user address
     * @param amount The amount to calculate the fee on
     * @return referralFee The referral fee
     */
    function quoteReferralFee(
        address user,
        uint256 amount
    ) external view returns (uint256 referralFee) {
        uint256 bps = getReferralBpsFor(user);

        if (bps > 0) {
            referralFee = (amount * bps) / 1e4;
        }
    }

    /**
     * @notice Callable by the vault with the address of the referred user
     * @param user The address of the referred user
     * @return totalReferralBps The total referral bps that the calling contract should deduct from the protocol fee
     */
    function getReferralBpsFor(
        address user
    ) public view returns (uint256 totalReferralBps) {
        if (
            (validUntil < block.timestamp) || (referredBy[user] == address(0))
        ) {
            return 0;
        }

        totalReferralBps = directRefFeeBps;
        if (indirectReferral[user] != address(0)) {
            totalReferralBps += indirectRefFeeBps;
        }
    }

    // User functions

    /**
     * @notice Claims the referral reward for a given base token for the msg.sender
     * @param token The token address
     */
    function claimReferralReward(
        address token
    ) external nonReentrant whenNotPaused {
        uint256 reward = _referrerBalances[msg.sender][token];

        if (reward < payoutThreshold[token])
            revert ReferralManager_PayoutBelowThreshold();
        if (reward == 0) revert ReferralManager_ZeroPayout();

        _referrerBalances[msg.sender][token] = 0;
        IERC20(token).safeTransfer(msg.sender, reward);

        emit ReferralPaidOut(msg.sender, token, reward);
    }

    // Admin functions

    /**
     * @notice Sets the direct referral fee
     * @param directRefFeeBps_ The direct referral fee in basis points
     */
    function setDirectRefFeeBps(uint256 directRefFeeBps_) external onlyOwner {
        directRefFeeBps = directRefFeeBps_;
        emit DirectRefFeeBpsSet(directRefFeeBps);
    }

    /**
     * @notice Sets the indirect referral fee
     * @param indirectRefFeeBps_ The indirect referral fee in basis points
     */
    function setIndirectRefFeeBps(
        uint256 indirectRefFeeBps_
    ) external onlyOwner {
        indirectRefFeeBps = indirectRefFeeBps_;
        emit IndirectRefFeeBpsSet(indirectRefFeeBps);
    }

    /**
     * @notice Sets the referral deadline
     * @param validUntil_ The referral deadline
     */
    function setValidUntil(uint256 validUntil_) external onlyOwner {
        validUntil = validUntil_;
        emit ReferralDeadlineSet(validUntil);
    }

    /**
     * @notice Sets the payout threshold for a token
     * @param tokens The token addresses
     * @param thresholds The payout thresholds
     */
    function setPayoutThreshold(
        address[] calldata tokens,
        uint256[] calldata thresholds
    ) external onlyOwner {
        if (tokens.length != thresholds.length)
            revert ReferralManager_ArrayLengthMismatch();

        for (uint256 i; i < tokens.length; ) {
            payoutThreshold[tokens[i]] = thresholds[i];
            emit PayoutThresholdSet(tokens[i], thresholds[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Sets the vault whitelist status
     * @param vault The vault address
     * @param enable The status of the vault
     */
    function setWhitelistedVault(
        address vault,
        bool enable
    ) external onlyOwner {
        whitelistedVault[vault] = enable;
        emit WhitelistedVaultSet(vault, enable);
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
     * @notice Gets the referral reward for a user
     * @param user The user address
     * @param token The token address
     * @return reward The reward amount
     */
    function getReferralRewardFor(
        address user,
        address token
    ) external view returns (uint256 reward) {
        reward = _referrerBalances[user][token];
    }
}
