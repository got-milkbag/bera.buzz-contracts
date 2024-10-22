// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Math64x64.sol";

library PriceConverter {
    /**
     * @notice Converts a price in wei to the initial square root price in Q64.64 format
     * @param priceInWei The price in wei (e.g., 0.007 * 1e18 for a price of 0.007)
     * @param baseDecimals The number of decimals for the base token
     * @param quoteDecimals The number of decimals for the quote token
     * @return The initial price in Q64.64 square root format as uint128
     */
    function calculateInitialPrice(uint256 priceInWei, uint8 baseDecimals, uint8 quoteDecimals) internal pure returns (uint128) {
        // To maintain precision for small numbers:
        // 1. First scale up the price to maintain precision
        // 2. Perform the decimal adjustment
        // 3. Then take the square root

        // Scale up by 2^64 first to maintain precision
        uint256 scaledPrice = priceInWei << 64;

        // Adjust for decimal differences
        if (quoteDecimals > baseDecimals) {
            scaledPrice = scaledPrice * (10 ** (quoteDecimals - baseDecimals));
        } else if (baseDecimals > quoteDecimals) {
            scaledPrice = scaledPrice / (10 ** (baseDecimals - quoteDecimals));
        }

        // Take the square root of the scaled price
        uint256 sqrtPrice = sqrt(scaledPrice);

        // Ensure the result fits in uint128
        require(sqrtPrice <= type(uint128).max, "Price overflow");

        return uint128(sqrtPrice);
    }

    /**
     * @notice Calculate the square root of a number
     * @param x The number to calculate the square root of
     * @return The square root of x
     */
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;

        uint256 xx = x;
        uint256 r = 1;

        if (xx >= 0x100000000000000000000000000000000) {
            xx >>= 128;
            r <<= 64;
        }
        if (xx >= 0x10000000000000000) {
            xx >>= 64;
            r <<= 32;
        }
        if (xx >= 0x100000000) {
            xx >>= 32;
            r <<= 16;
        }
        if (xx >= 0x10000) {
            xx >>= 16;
            r <<= 8;
        }
        if (xx >= 0x100) {
            xx >>= 8;
            r <<= 4;
        }
        if (xx >= 0x10) {
            xx >>= 4;
            r <<= 2;
        }
        if (xx >= 0x4) {
            r <<= 1;
        }

        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;

        uint256 r1 = x / r;
        return r < r1 ? r : r1;
    }
}
