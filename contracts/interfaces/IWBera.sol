// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IWBera {
    function deposit() external payable;

    function transfer(address to, uint value) external returns (bool);

    function withdraw(uint) external;

    function approve(address spender, uint value) external returns (bool);

    function balanceOf(address) external view returns (uint256);
}
