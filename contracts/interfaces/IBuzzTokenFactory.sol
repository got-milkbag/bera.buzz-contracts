// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBuzzTokenFactory {
    function createToken(
        string[2] calldata metadata, //name, symbol
        address[3] calldata addr, //baseToken, vault, taxTo
        uint256 baseAmount,
        bytes32 salt,
        uint256 tax
    ) external payable returns (address token);
}
