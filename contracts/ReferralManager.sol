// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IReferralManager.sol";

contract ReferralManager is Ownable, ReentrancyGuard, IReferralManager {
    using SafeERC20 for IERC20;

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

    event ReferralSet(address indexed referrer, address indexed user);
    event IndirectReferralSet(address indexed referrer, address indexed user, address indexed indirectReferrer);
    event ReferralRewardReceived(address indexed referrer, address indexed token, uint256 reward, bool isDirect);
    event ReferralPaidOut(address indexed referrer, address indexed token, uint256 reward);
    event DirectRefFeeBpsSet(uint256 directRefFeeBps);
    event IndirectRefFeeBpsSet(uint256 indirectRefFeeBps);
    event ReferralDeadlineSet(uint256 validUntil);
    event PayoutThresholdSet(address token, uint256 payoutThreshold);
    event whitelistedVaultSet(address indexed vault, bool status);

    uint256 public constant MAX_FEE_BPS = 10000;

    // Fees should be passed in bps of the protocol fee to be received by the referrer
    uint256 public directRefFeeBps; // eg 100 -> 1%
    uint256 public indirectRefFeeBps; // eg 100 -> 1%

    uint256 public validUntil;

    mapping(address => address) public referredBy;
    mapping(address => address) public indirectReferral;
    mapping(address => mapping(address => uint256)) private _referrerBalances;
    mapping(address => bool) public whitelistedVault;
    mapping(address => uint256) public payoutThreshold;

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
            if (tokens.length != _payoutThresholds.length) revert ReferralManager_ArrayLengthMismatch();
            for (uint256 i = 0; i < tokens.length; i++) {
                payoutThreshold[tokens[i]] = _payoutThresholds[i];
                emit PayoutThresholdSet(tokens[i], _payoutThresholds[i]);
            }
        }
    }

    // Vault functions

    /// @notice Callable by the vault with the address of the referred user
    function receiveReferral(address user, address token, uint256 amount) external nonReentrant {
        if (!whitelistedVault[msg.sender]) revert ReferralManager_Unauthorised();
        address referrer = referredBy[user];

        if (validUntil < block.timestamp) revert ReferralManager_ReferralExpired();
        if (referrer == address(0)) revert ReferralManager_AddressZero();
        if (amount == 0) revert ReferralManager_ZeroPayout();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        if (indirectReferral[user] != address(0)) {
            // If there is an indirect referral
            uint256 indirectReferralAmount = (amount * indirectRefFeeBps) / MAX_FEE_BPS;
            _referrerBalances[indirectReferral[user]][token] += indirectReferralAmount;
            emit ReferralRewardReceived(indirectReferral[user], token, indirectReferralAmount, false);

            uint256 directReferralAmount = amount - indirectReferralAmount;
            _referrerBalances[referrer][token] += directReferralAmount;
            emit ReferralRewardReceived(referrer, token, directReferralAmount, true);
        } else {
            _referrerBalances[referrer][token] += amount;
            emit ReferralRewardReceived(referrer, token, amount, true);
        }
    }

    function setReferral(address referrer, address user) external nonReentrant {
        if (!whitelistedVault[msg.sender]) revert ReferralManager_Unauthorised();

        if ((referredBy[user] != address(0)) || (referrer == user) || (referrer == address(0))) {
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

    /// @notice Callable by the vault with the address of the referred user
    /// @param user The address of the referred user
    /// @return totalReferralBps The total referral bps that the calling contract should deduct from the protocol fee and pass to the Referral Manager via receiveReferral
    function getReferralBpsFor(address user) external view returns (uint256 totalReferralBps) {
        if ((validUntil < block.timestamp) || (referredBy[user] == address(0))) {
            return 0;
        }

        totalReferralBps = directRefFeeBps;
        if (indirectReferral[user] != address(0)) {
            totalReferralBps += indirectRefFeeBps;
        }
    }

    // User functions

    function claimReferralReward(address token) external nonReentrant {
        uint256 reward = _referrerBalances[msg.sender][token];

        if (reward < payoutThreshold[token]) revert ReferralManager_PayoutBelowThreshold();
        if (reward == 0) revert ReferralManager_ZeroPayout();

        _referrerBalances[msg.sender][token] = 0;
        IERC20(token).safeTransfer(msg.sender, reward);

        emit ReferralPaidOut(msg.sender, token, reward);
    }

    // Admin functions

    function setDirectRefFeeBps(uint256 _directRefFeeBps) external onlyOwner {
        directRefFeeBps = _directRefFeeBps;
        emit DirectRefFeeBpsSet(directRefFeeBps);
    }

    function setIndirectRefFeeBps(uint256 _indirectRefFeeBps) external onlyOwner {
        indirectRefFeeBps = _indirectRefFeeBps;
        emit IndirectRefFeeBpsSet(indirectRefFeeBps);
    }

    function setValidUntil(uint256 _validUntil) external onlyOwner {
        validUntil = _validUntil;
        emit ReferralDeadlineSet(validUntil);
    }

    function setPayoutThreshold(address[] calldata tokens, uint256[] calldata thresholds) external onlyOwner {
        if (tokens.length != thresholds.length) revert ReferralManager_ArrayLengthMismatch();

        for (uint256 i = 0; i < tokens.length; i++) {
            payoutThreshold[tokens[i]] = thresholds[i];
            emit PayoutThresholdSet(tokens[i], thresholds[i]);
        }
    }

    function setWhitelistedVault(address vault, bool enable) external onlyOwner {
        whitelistedVault[vault] = enable;
        emit whitelistedVaultSet(vault, enable);
    }

    // View functions

    function getReferralRewardFor(address user, address token) external view returns (uint256 reward) {
        reward = _referrerBalances[user][token];
    }
}
