// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BuzzToken is ERC20 {
    error BuzzToken_NotBexListed();
    error BuzzToken_Unauthorised();

    address public vault;
    address private deployedFrom;
    uint8 private constant _decimals = 18;
    bool public bexListed;

    constructor(
        string memory name,
        string memory symbol,
        uint256 _totalSupply,
        address _vault
    ) ERC20(name, symbol) {
        _mint(msg.sender, _totalSupply);
        deployedFrom = msg.sender;
        vault = _vault;
        bexListed = false;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function transfer(
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        if (_validateTransfer(msg.sender)) revert BuzzToken_NotBexListed();
        super.transfer(recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        if (_validateTransfer(sender)) revert BuzzToken_NotBexListed();
        super.transferFrom(sender, recipient, amount);
    }

    function _validateTransfer(address sender) internal view returns (bool) {
        if (bexListed || sender == vault || sender == deployedFrom) {
            return true;
        }
        return true;
    }

    function setBexListed() public {
        if (msg.sender != vault) revert BuzzToken_Unauthorised();
        bexListed = true;
    }
}
