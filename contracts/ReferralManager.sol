// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IReferralManager.sol";

contract ReferralManager is Ownable, ReentrancyGuard, IReferralManager {
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

    event ReferralSet(address indexed referrer, address indexed user);
    event IndirectReferralSet(address indexed referrer, address indexed user, address indexed indirectReferrer);
    event ReferralRewardReceived(address indexed referrer, uint256 reward);
    event ReferralPaidOut(address indexed referrer, uint256 reward);
    event DirectRefFeeBpsSet(uint256 directRefFeeBps);
    event IndirectRefFeeBpsSet(uint256 indirectRefFeeBps);
    event ReferralDeadlineSet(uint256 validUntil);
    event PayoutThresholdSet(uint256 payoutThreshold);
    event WhitelistedVaultSet(address indexed vault, bool status);

    uint256 public constant MAX_FEE_BPS = 10000;

    // Fees should be passed in bps of the protocol fee to be received by the referrer
    uint256 public directRefFeeBps; // eg 100 -> 1%
    uint256 public indirectRefFeeBps; // eg 100 -> 1%

    uint256 public validUntil;
    uint256 public payoutThreshold;

    mapping(address => address) public referredBy;
    mapping(address => address) public indirectReferral;
    mapping(address => ReferrerInfo) public referrerInfo;
    mapping(address => bool) public whitelistedVaults;

    struct ReferrerInfo {
        uint256 rewardToPayOut;
        uint256 rewardPaidOut;
        uint256 referralCount;
        uint256 indirectReferralCount;
    }

    /// @notice Fee bps is the % of the protocol fee that the referrer will receive
    constructor(uint256 _directRefFeeBps, uint256 _indirectRefFeeBps, uint256 _validUntil, uint256 _payoutThreshold) {
        directRefFeeBps = _directRefFeeBps;
        indirectRefFeeBps = _indirectRefFeeBps;
        validUntil = _validUntil;
        payoutThreshold = _payoutThreshold;
    }

    // Vault functions

    /// @notice Callable by the vault with the address of the referred user
    function receiveReferral(address user) external payable nonReentrant {
        if (!whitelistedVaults[msg.sender]) revert ReferralManager_Unauthorised();
        address referrer = referredBy[user];
        uint256 amount = msg.value;

        if (validUntil < block.timestamp) revert ReferralManager_ReferralExpired();
        if (referrer == address(0)) revert ReferralManager_AddressZero();
        if (amount == 0) revert ReferralManager_ZeroPayout();


        if (indirectReferral[user] != address(0)) {
            uint256 indirectReferralAmount = (amount * indirectRefFeeBps) / MAX_FEE_BPS;
            referrerInfo[indirectReferral[user]].rewardToPayOut += indirectReferralAmount;
            emit ReferralRewardReceived(indirectReferral[user], indirectReferralAmount);

            uint256 directReferralAmount = amount - indirectReferralAmount;
            referrerInfo[referrer].rewardToPayOut += directReferralAmount;
            emit ReferralRewardReceived(referrer, directReferralAmount);
        } else {
            referrerInfo[referrer].rewardToPayOut += amount;
            emit ReferralRewardReceived(referrer, amount);
        }
    }

    function setReferral(address referrer, address user) external nonReentrant {
        if (!whitelistedVaults[msg.sender]) revert ReferralManager_Unauthorised();

        if ((referredBy[user] != address(0)) || (referrer == user) || (referrer == address(0))) {
            return;
        }

        referredBy[user] = referrer;
        referrerInfo[referrer].referralCount += 1;
        emit ReferralSet(referrer, user);

        address indirectReferrer = referredBy[referrer];
        if (indirectReferrer != address(0)) {
            indirectReferral[user] = indirectReferrer;
            referrerInfo[indirectReferrer].indirectReferralCount += 1;
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

    function claimReferralReward() external nonReentrant {
        ReferrerInfo storage info = referrerInfo[msg.sender];
        uint256 reward = info.rewardToPayOut;
        if (reward < payoutThreshold) revert ReferralManager_PayoutBelowThreshold();
        if (reward == 0) revert ReferralManager_ZeroPayout();

        // @dev come back here
        info.rewardToPayOut = info.rewardToPayOut - reward;
        info.rewardPaidOut += reward;

        (bool success, ) = msg.sender.call{value: reward}("");
        if (!success) revert ReferralManager_RewardTransferFailed();
        
        emit ReferralPaidOut(msg.sender, reward);
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

    function setPayoutThreshold(uint256 _payoutThreshold) external onlyOwner {
        payoutThreshold = _payoutThreshold;
        emit PayoutThresholdSet(payoutThreshold);
    }

    function setWhitelistedVault(address vault, bool enable) external onlyOwner {
        whitelistedVaults[vault] = enable;
        emit WhitelistedVaultSet(vault, enable);
    }
}
