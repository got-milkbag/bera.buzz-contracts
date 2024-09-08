// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ReferralManager is Ownable, ReentrancyGuard {
    error ReferralManager_Unauthorised();
    error ReferralManager_InvalidParams();
    error ReferralManager_RewardTransferFailed();
    error ReferralManager_PayoutBelowThreshold();

    event ReferralSet(address indexed referrer, address indexed user);
    event IndirectReferralSet(address indexed referrer, address indexed user, address indexed indirectReferrer);
    event ReferralRewardReceived(address indexed referrer, uint256 reward);
    event ReferralPaidOut(address indexed referrer, uint256 reward);

    // Fees should be passed in bps of the protocol fee to be received by the referrer
    uint256 public directRefFeeBps; // eg 100 -> 1%
    uint256 public indirectRefFeeBps; // eg 100 -> 1%
    uint256 public constant MAX_FEE_BPS = 10000;

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

    function setReferral(address referrer, address user) public nonReentrant {
        if (whitelistedVaults[msg.sender] == false) revert ReferralManager_Unauthorised();

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
    /// @return The total referral bps that the calling contract should deduct from the protocol fee and pass to the Referral Manager via receiveReferral
    function getReferreralBpsFor(address user) public view returns (uint256) {
        if ((validUntil < block.timestamp) || (referredBy[user] == address(0))) {
            return 0;
        }

        uint256 totalReferralBps = directRefFeeBps;
        if (indirectReferral[user] != address(0)) {
            totalReferralBps += indirectRefFeeBps;
        }
        return totalReferralBps;
    }

    /// @notice Callable by the vault with the address of the referred user
    function receiveReferral(address user) public payable nonReentrant {
        if (whitelistedVaults[msg.sender] == false) revert ReferralManager_Unauthorised();
        address referrer = referredBy[user];
        uint256 amount = msg.value;

        if ((validUntil < block.timestamp) || (referrer == address(0)) || (amount == 0)) {
            revert ReferralManager_InvalidParams();
        }

        uint256 directRefBps = MAX_FEE_BPS - directRefFeeBps;
        if (indirectReferral[user] != address(0)) {
            directRefBps -= indirectRefFeeBps;
            uint256 indirectReferralAmount = (amount * indirectRefFeeBps) / MAX_FEE_BPS;
            referrerInfo[indirectReferral[user]].rewardToPayOut += indirectReferralAmount;
            emit ReferralRewardReceived(indirectReferral[user], indirectReferralAmount);
        }
        uint256 directReferralAmount = (amount * directRefBps) / MAX_FEE_BPS;
        referrerInfo[referrer].rewardToPayOut += directReferralAmount;
        emit ReferralRewardReceived(referrer, directReferralAmount);
    }

    // User functions

    function claimReferralReward() public nonReentrant {
        ReferrerInfo storage info = referrerInfo[msg.sender];
        uint256 reward = info.rewardToPayOut;
        if (reward < payoutThreshold) revert ReferralManager_PayoutBelowThreshold();

        info.rewardToPayOut = info.rewardToPayOut - reward;
        info.rewardPaidOut += reward;

        (bool success, ) = msg.sender.call{value: reward}("");
        if (!success) revert ReferralManager_RewardTransferFailed();
        emit ReferralPaidOut(msg.sender, reward);
    }

    // Admin functions

    function setDirectRefFeeBps(uint256 _directRefFeeBps) public onlyOwner {
        directRefFeeBps = _directRefFeeBps;
    }

    function setIndirectRefFeeBps(uint256 _indirectRefFeeBps) public onlyOwner {
        indirectRefFeeBps = _indirectRefFeeBps;
    }

    function setValidUntil(uint256 _validUntil) public onlyOwner {
        validUntil = _validUntil;
    }

    function setPayoutThreshold(uint256 _payoutThreshold) public onlyOwner {
        payoutThreshold = _payoutThreshold;
    }

    function setWhitelistedVault(address vault, bool enable) public onlyOwner {
        whitelistedVaults[vault] = enable;
    }
}
