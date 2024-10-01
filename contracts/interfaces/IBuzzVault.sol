// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IBuzzVault {
    function buy(address token, uint256 minTokens, address affiliate) external payable;

    function sell(address token, uint256 tokenAmount, uint256 minBera, address affiliate) external;

    function registerToken(address token, uint256 tokenBalance) external;

    function getMarketCapFor(address token) external view returns (uint256 marketCap);

    function quote(address token, uint256 amount, bool isBuyOrder) external view returns (uint256 amountOut, uint256 pricePerToken);
}
