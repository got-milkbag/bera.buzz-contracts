// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBuzzTokenFactory {
    function createToken(
        string[2] calldata metadata, //name, symbol
        address[2] calldata addr, //baseToken, vault
        uint256[2] calldata raiseData, //initialReserves, finalReserves
        uint256 baseAmount,
        bytes32 salt
    ) external payable returns (address token);

    function isDeployed(address token) external view returns (bool);
}
