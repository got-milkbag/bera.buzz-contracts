// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BuzzToken is ERC20 {
    uint8 private constant DECIMALS = 18;
    
    string public description;
    string public image;

    constructor(
        string memory name,
        string memory symbol,
        string memory _description,
        string memory _image,
        uint256 _totalSupply,
        address mintTo
    ) ERC20(name, symbol) {
        _mint(mintTo, _totalSupply);
        description = _description;
        image = _image;
    }

    function decimals() public pure override returns (uint8 _decimals) {
        _decimals = DECIMALS;
    }
}
