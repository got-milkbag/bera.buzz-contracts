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
    event Trade(address indexed user, address indexed token, uint256 tokenAmount, uint256 beraAmount, bool isBuyOrder, address vault);
    event TokenCreated(address token, string name, string symbol, string description, string image, address deployer, address vault);
    event EventSetterSet(address indexed contractSet, bool status);

    mapping(address => bool) public eventSetters;

    constructor(address[] memory _eventSetters) {
        for (uint256 i; i < _eventSetters.length; ++i) {
            eventSetters[_eventSetters[i]] = true;
        }
    }

    function emitTrade(
        address user, 
        address token, 
        uint256 tokenAmount, 
        uint256 beraAmount, 
        bool isBuyOrder
    ) external {
        if (!eventSetters[msg.sender]) revert BuzzEventTracker_Unauthorized();
        emit Trade(user, token, tokenAmount, beraAmount, isBuyOrder, msg.sender);
    }

    function emitTokenCreated(
        address token,
        string calldata name,
        string calldata symbol,
        string calldata description,
        string calldata image,
        address deployer,
        address vault
    ) external {
        if (!eventSetters[msg.sender]) revert BuzzEventTracker_Unauthorized();
        emit TokenCreated(token, name, symbol, description, image, deployer, vault);
    }

    function setEventSetter(address _contract, bool enable) external onlyOwner {
        if (_contract == address(0)) revert BuzzEventTracker_AddressZero();
        eventSetters[_contract] = enable;

        emit EventSetterSet(_contract, enable);
    }
}
