// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract DecimalsCounterOptimized {
    function countDecimals(uint256 _balanceInWei) public pure returns (uint8) {
        if (_balanceInWei < 10) return 1;
        if (_balanceInWei < 100) return 2;
        if (_balanceInWei < 1000) return 3;
        if (_balanceInWei < 10000) return 4;
        if (_balanceInWei < 100000) return 5;
        if (_balanceInWei < 1000000) return 6;
        if (_balanceInWei < 10000000) return 7;
        if (_balanceInWei < 100000000) return 8;
        if (_balanceInWei < 1000000000) return 9;
        if (_balanceInWei < 10000000000) return 10;
        if (_balanceInWei < 100000000000) return 11;
        if (_balanceInWei < 1000000000000) return 12;
        if (_balanceInWei < 10000000000000) return 13;
        if (_balanceInWei < 100000000000000) return 14;
        if (_balanceInWei < 1000000000000000) return 15;
        if (_balanceInWei < 10000000000000000) return 16;
        if (_balanceInWei < 100000000000000000) return 17;
        if (_balanceInWei < 1000000000000000000) return 18;
        if (_balanceInWei < 10000000000000000000) return 19;
        if (_balanceInWei < 100000000000000000000) return 20;
        if (_balanceInWei < 1000000000000000000000) return 21;
        if (_balanceInWei < 10000000000000000000000) return 22;
        if (_balanceInWei < 100000000000000000000000) return 23;
        if (_balanceInWei < 1000000000000000000000000) return 24;
        if (_balanceInWei < 10000000000000000000000000) return 25;
        if (_balanceInWei < 100000000000000000000000000) return 26;
        if (_balanceInWei < 1000000000000000000000000000) return 27;
        if (_balanceInWei < 10000000000000000000000000000) return 28;
        if (_balanceInWei < 100000000000000000000000000000) return 29;
        if (_balanceInWei < 1000000000000000000000000000000) return 30;
        if (_balanceInWei < 10000000000000000000000000000000) return 31;
        if (_balanceInWei < 100000000000000000000000000000000) return 32;
        if (_balanceInWei < 1000000000000000000000000000000000) return 33;
        if (_balanceInWei < 10000000000000000000000000000000000) return 34;
        if (_balanceInWei < 100000000000000000000000000000000000) return 35;
        if (_balanceInWei < 1000000000000000000000000000000000000) return 36;
        if (_balanceInWei < 10000000000000000000000000000000000000) return 37;
        if (_balanceInWei < 100000000000000000000000000000000000000) return 38;
        if (_balanceInWei < 1000000000000000000000000000000000000000) return 39;
        if (_balanceInWei < 10000000000000000000000000000000000000000) return 40;
        if (_balanceInWei < 100000000000000000000000000000000000000000) return 41;
        if (_balanceInWei < 1000000000000000000000000000000000000000000) return 42;
        if (_balanceInWei < 10000000000000000000000000000000000000000000) return 43;
        if (_balanceInWei < 100000000000000000000000000000000000000000000) return 44;
        if (_balanceInWei < 1000000000000000000000000000000000000000000000) return 45;
        if (_balanceInWei < 10000000000000000000000000000000000000000000000) return 46;
        if (_balanceInWei < 100000000000000000000000000000000000000000000000) return 47;
        if (_balanceInWei < 1000000000000000000000000000000000000000000000000) return 48;
        if (_balanceInWei < 10000000000000000000000000000000000000000000000000) return 49;
        return 50; // Maximum case: 10^50 has 51 digits
    }
}
