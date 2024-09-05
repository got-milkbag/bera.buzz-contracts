// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./BuzzToken.sol";
import "./interfaces/IBuzzVault.sol";

contract BuzzTokenFactory is Ownable {
    error BuzzToken_TokenCreationDisabled();
    error BuzzToken_InvalidParams();

    event TokenCreated(address token);

    bool public allowTokenCreation;
    uint256 public constant totalSupplyOfTokens = 1000000000000000000000000000;

    mapping(address => bool) public vaults;
    mapping(address => bool) public isDeployed;

    constructor() {}

    function createToken(string memory name, string memory symbol, address vault) public returns (address) {
        if (!allowTokenCreation) revert BuzzToken_TokenCreationDisabled();
        if (vaults[vault] == false) revert BuzzToken_InvalidParams();
        address token = address(new BuzzToken(name, symbol, totalSupplyOfTokens));
        IERC20(token).approve(vault, totalSupplyOfTokens);
        IBuzzVault(vault).registerToken(token, totalSupplyOfTokens);
        isDeployed[token] = true;

        emit TokenCreated(token);
        return address(token);
    }

    function setVault(address _vault, bool enable) public onlyOwner {
        if (_vault == address(0)) revert BuzzToken_InvalidParams();
        vaults[_vault] = enable;
    }

    function setAllowTokenCreation(bool _allowTokenCreation) public onlyOwner {
        allowTokenCreation = _allowTokenCreation;
    }
}
