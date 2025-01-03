// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IBuzzToken.sol";

contract BuzzToken is ERC20, AccessControl, IBuzzToken {
    /// @dev access control minter role.
    bytes32 public immutable MINTER_ROLE;
    /// @dev The number of decimals
    uint8 private constant DECIMALS = 18;

    constructor(
        string memory name,
        string memory symbol,
        uint256 _initialSupply,
        address mintTo,
        address _owner
    ) ERC20(name, symbol) {
        _mint(mintTo, _initialSupply);
        MINTER_ROLE = keccak256("MINTER_ROLE");
        _grantRole(MINTER_ROLE, _owner);
    }

    function decimals() public pure override returns (uint8 _decimals) {
        _decimals = DECIMALS;
    }

    function mint(address account, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(account, amount);
    }

    function totalSupply() public view override(ERC20, IBuzzToken) returns (uint256) {
        return super.totalSupply();
    }
}
