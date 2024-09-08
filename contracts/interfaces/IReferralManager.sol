// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IReferralManager {
    function setReferral(address referrer, address user) external;

    function getReferreralBpsFor(address user) external view returns (uint256);

    function receiveReferral(address user) external payable;
}
