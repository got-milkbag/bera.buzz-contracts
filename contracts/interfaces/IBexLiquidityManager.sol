// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBexLiquidityManager {
    function createPoolAndAdd(
        address token,
        address baseToken,
        address user,
        uint256 amount,
        uint256 baseAmount
    ) external returns (address pool);
}
