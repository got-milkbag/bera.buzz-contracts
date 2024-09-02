// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./BuzzToken.sol";
import "./interfaces/IBuzzVault.sol";

contract BuzzTokenFactory is Ownable {
    error BuzzToken_TokenCreationDisabled();

    address public vault;
    bool public allowTokenCreation;
    uint256 public constant totalSupplyOfTokens = 1000000000000000000000000000;

    mapping(address => bool) public isDeployed;

    constructor() {}

    function createToken(
        string memory name,
        string memory symbol
    ) public returns (address) {
        if (!allowTokenCreation) revert BuzzToken_TokenCreationDisabled();
        address token = address(
            new BuzzToken(name, symbol, totalSupplyOfTokens, vault)
        );
        IERC20(token).approve(vault, totalSupplyOfTokens);
        IBuzzVault(vault).registerToken(token, totalSupplyOfTokens);
        isDeployed[token] = true;
        return address(token);
    }

    function setVault(address _vault) public onlyOwner {
        vault = _vault;
    }

    function setAllowTokenCreation(bool _allowTokenCreation) public onlyOwner {
        allowTokenCreation = _allowTokenCreation;
    }
}
