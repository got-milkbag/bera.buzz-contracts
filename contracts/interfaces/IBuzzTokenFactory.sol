// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IBuzzTokenFactory {
    function createToken(string calldata name, string calldata symbol, address vault, bytes32 salt) external payable returns (address token);
}
