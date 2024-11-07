// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IReferralManager {
    function setReferral(address referrer, address user) external;

    function getReferralBpsFor(address user) external view returns (uint256 bps);

    function receiveReferral(address user, address token, uint256 amount) external;
}
