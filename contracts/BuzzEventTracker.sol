// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

contract BuzzEventTracker is Ownable {
    error BuzzEventTracker_Unauthorized();
    mapping(address => bool) public eventSetters;

    // Amounts emitted
    event trade(address indexed user, address indexed token, uint256 tokenAmount, uint256 beraAmount, bool isBuyOrder, address vault);
    event tokenCreated(address token, string name, string symbol, address vault);

    constructor(address[] memory _eventSetters) {
        for (uint256 i = 0; i < _eventSetters.length; i++) {
            eventSetters[_eventSetters[i]] = true;
        }
    }

    function emitTrade(address user, address token, uint256 tokenAmount, uint256 beraAmount, bool isBuyOrder) public {
        if (!eventSetters[msg.sender]) revert BuzzEventTracker_Unauthorized();
        emit trade(user, token, tokenAmount, beraAmount, isBuyOrder, msg.sender);
    }

    function emitTokenCreated(address token, string memory name, string memory symbol, address vault) public {
        if (!eventSetters[msg.sender]) revert BuzzEventTracker_Unauthorized();
        emit tokenCreated(token, name, symbol, vault);
    }

    function setEventSetter(address _contract, bool enable) public onlyOwner {
        if (_contract == address(0)) revert();
        eventSetters[_contract] = enable;
    }
}
