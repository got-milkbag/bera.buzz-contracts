// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBexLiquidityManager {
    function createPoolAndAdd(address token, address baseToken, uint256 netBaseAmount, uint256 amount) external returns (address);
    function predictConduitAddress(address token, address baseToken) external view returns (address);
}
