// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBuzzToken {
    function mint(address account, uint256 amount) external;
    function totalSupply() external view returns (uint256);
    function setBexPoolAddress(address poolAddress) external;

    function TAX() external view returns (uint256);
}