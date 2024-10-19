// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IBuzzEventTracker {
    function emitTrade(address user, address token, uint256 tokenAmount, uint256 beraAmount, uint256 lastPrice, bool isBuyOrder) external;

    function emitTokenCreated(
        address token,
        string calldata name,
        string calldata symbol,
        string calldata description,
        string calldata image,
        address deployer,
        address vault
    ) external;
}
