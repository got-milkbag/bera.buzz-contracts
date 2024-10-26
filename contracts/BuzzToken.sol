// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BuzzToken is ERC20 {
    uint8 private constant DECIMALS = 18;

    constructor(string memory name, string memory symbol, uint256 _totalSupply, address mintTo) ERC20(name, symbol) {
        _mint(mintTo, _totalSupply);
    }

    function decimals() public pure override returns (uint8 _decimals) {
        _decimals = DECIMALS;
    }
}
