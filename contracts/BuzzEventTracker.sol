// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IBuzzEventTracker.sol";

contract BuzzEventTracker is Ownable, IBuzzEventTracker {
    /// @notice Error code emitted when the caller is not authorized
    error BuzzEventTracker_Unauthorized();
    /// @notice Error code emitted when the address is zero
    error BuzzEventTracker_AddressZero();

    // Amounts emitted
    event Trade(
        address indexed user,
        address indexed token,
        uint256 tokenAmount,
        uint256 beraAmount,
        uint256 lastPrice,
        bool isBuyOrder,
        address vault
    );
    event TokenCreated(address indexed token, string name, string symbol, address deployer, address vault, uint256 tax);
    event EventSetterSet(address indexed contractSet, bool status);

    mapping(address => bool) public eventSetters;

    constructor(address[] memory _eventSetters) {
        for (uint256 i; i < _eventSetters.length; ++i) {
            eventSetters[_eventSetters[i]] = true;
        }
    }

    function emitTrade(address user, address token, uint256 tokenAmount, uint256 beraAmount, uint256 lastPrice, bool isBuyOrder) external {
        if (!eventSetters[msg.sender]) revert BuzzEventTracker_Unauthorized();
        emit Trade(user, token, tokenAmount, beraAmount, lastPrice, isBuyOrder, msg.sender);
    }

    function emitTokenCreated(
        address token,
        string calldata name,
        string calldata symbol,
        address deployer,
        address vault,
        uint256 tax
    ) external {
        if (!eventSetters[msg.sender]) revert BuzzEventTracker_Unauthorized();
        emit TokenCreated(token, name, symbol, deployer, vault, tax);
    }

    function setEventSetter(address _contract, bool enable) external onlyOwner {
        if (_contract == address(0)) revert BuzzEventTracker_AddressZero();
        eventSetters[_contract] = enable;

        emit EventSetterSet(_contract, enable);
    }
}
