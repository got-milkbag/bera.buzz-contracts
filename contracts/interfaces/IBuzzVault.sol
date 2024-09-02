// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IBuzzVault {
    function registerToken(address token, uint256 tokenBalance) external;
}
