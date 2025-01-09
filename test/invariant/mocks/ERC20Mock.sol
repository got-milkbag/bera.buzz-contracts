// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    uint8 internal immutable dec;

    constructor(string memory _name, string memory _symbol, uint8 _dec) ERC20(_name, _symbol) {
        dec = _dec;
    }

    function decimals() public view virtual override returns (uint8) {
        return dec;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}