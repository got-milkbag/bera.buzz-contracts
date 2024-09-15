// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract CrocQueryMock {
    uint128 private _price;

    constructor(uint128 price) {
        _price = price;
    }

    function setPrice(uint128 price) external {
        _price = price; // eg 83238796252293901415
    }

    function queryPrice(address, address, uint256) external view returns (uint128) {
        return _price;
    }
}
