// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IBuzzEventTracker {
    function emitTrade(address user, address token, uint256 tokenAmount, uint256 beraAmount, bool isBuyOrder) external;

    function emitTokenCreated(address token, string memory name, string memory symbol, address vault) external;
}
