// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IBuzzVault {
    function buy(address token, uint256 baseAmount, uint256 minTokensOut, address affiliate) external;

    function buyNative(address token, uint256 minTokensOut, address affiliate) external payable;

    function sell(address token, uint256 tokenAmount, uint256 minAmountOut, address affiliate, bool unwrap) external;

    function registerToken(address token, address baseToken, uint256 initialTokenBalance, uint256 initialReserves, uint256 finalReserves) external;

    function quote(
        address token,
        uint256 amount,
        bool isBuyOrder
    ) external view returns (uint256 amountOut, uint256 pricePerToken, uint256 pricePerBase);
}
