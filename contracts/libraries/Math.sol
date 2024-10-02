// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

library Math {
    /**
     * @dev returns the largest integer smaller than or equal to the square root of a positive integer
     *
     * @param _num a positive integer
     *
     * @return the largest integer smaller than or equal to the square root of the positive integer
     */
    function floorSqrt(uint256 _num) internal pure returns (uint256) {
        uint256 x = _num / 2 + 1;
        uint256 y = (x + _num / x) / 2;
        while (x > y) {
            x = y;
            y = (x + _num / x) / 2;
        }
        return x;
    }

    function sqrt(uint256 x) internal pure returns (uint256) {
        uint256 z = (x + 1) / 2; // a = x, b = 1, (a + b) / 2 >= sqrt(ab)
        uint256 y = x;
        while (z < y) { // y = (x/z + z)/2; z = sqrt(x)
            y = z;
            z = (x / z + z) / 2;
        }
        return z;
    }
}
