// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract BuzzEventTracker {
    event trade(address indexed user, address indexed token, uint256 tokenAmount, uint256 beraAmount, uint256 timestamp);
}
