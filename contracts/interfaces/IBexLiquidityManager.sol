pragma solidity ^0.8.19;

interface IBexLiquidityManager {
    function createPoolAndAdd(address token, uint256 amount, uint256 lastPrice) external payable;
}
