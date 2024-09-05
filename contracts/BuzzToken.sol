// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BuzzToken is ERC20 {
    uint8 private constant _decimals = 18;

    constructor(string memory name, string memory symbol, uint256 _totalSupply) ERC20(name, symbol) {
        _mint(msg.sender, _totalSupply);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
