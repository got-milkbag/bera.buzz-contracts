// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBuzzTokenFactory {
    function createToken(
        string calldata name,
        string calldata symbol,
        address vault,
        address taxTo,
        bytes32 salt,
        uint256 tax
    ) external payable returns (address token);
}
