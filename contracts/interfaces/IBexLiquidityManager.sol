// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBexLiquidityManager {
    function createPoolAndAdd(address token, uint256 amount) external payable returns (address);
}
