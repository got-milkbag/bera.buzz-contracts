// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ReferralManager is Ownable, ReentrancyGuard {
    mapping(address => address) public referredBy;
    mapping(address => address[]) public indirectReferrals;

    mapping(address => ReferrerInfo) public referrerInfo;

    struct ReferrerInfo {
        uint256 rewardToPayOut;
        uint256 rewardPaidOut;
        uint256 referralCount;
        uint256 indirectReferralCount;
    }

    // todo: max limit in indirect referrals
    uint256 public validUntil;

    constructor() {
        // save vault addresses or factory to register referrals
    }
}
