// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract User {
    constructor() payable {}

    function proxy(address target, bytes memory data) public returns (bool success, bytes memory err) {
        return target.call(data);
    }

    function approve(address target, address spender) public {
        ERC20(target).approve(spender, type(uint256).max);
    }
}