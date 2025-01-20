// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBexLiquidityManager {
    function createPoolAndAdd(
        address token,
        address baseToken,
        uint256 baseAmount,
        uint256 amount
    ) external;
}
