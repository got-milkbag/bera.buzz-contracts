// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library FixedPoint64 {
    uint256 private constant Q64_64 = 2 ** 64;
    uint256 private constant DECIMALS = 10 ** 18;

    /// @notice Decodes a Q64.64 value and returns the actual price in terms of the underlying tokens.
    /// @param sqrtPriceX64 The square root price in Q64.64 format.
    /// @return price The price of token0 in terms of token1, scaled to 18 decimal places.
    function decodeSqrtPriceX64(uint160 sqrtPriceX64) internal pure returns (uint256 price) {
        // Convert Q64.64 square root price to the actual price ratio
        // price = (sqrtPriceX64^2) / 2^64

        uint256 sqrtPriceX64Uint = uint256(sqrtPriceX64);

        // Compute the square of the sqrtPriceX64 (to get back to the price ratio)
        uint256 priceRatio = (sqrtPriceX64Uint * sqrtPriceX64Uint) / Q64_64;

        // Since both tokens have 18 decimals, we scale the price accordingly
        price = (priceRatio * DECIMALS) / Q64_64;
    }
}
