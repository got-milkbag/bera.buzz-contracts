// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract BexLPTokenMock {
    uint256 private _poolType;
    address private _baseToken;
    address private _quoteToken;

    constructor(uint256 _type, address base, address quote) {
        _poolType = _type;
        _baseToken = base;
        _quoteToken = quote;
    }

    function poolType() external view returns (uint256) {
        return _poolType;
    }

    function baseToken() external view returns (address) {
        return _baseToken;
    }

    function quoteToken() external view returns (address) {
        return _quoteToken;
    }
}
