pragma solidity ^0.8.19;

interface IBuzzTokenFactory {
    function createToken(
        string calldata name,
        string calldata symbol,
        string calldata description,
        string calldata image,
        address vault,
        bytes32 salt
    ) external returns (address token);
}