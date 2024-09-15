// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.19;

interface ICrocQuery {
    function queryPrice(address base, address quote, uint256 poolIdx) external view returns (uint128);
}
