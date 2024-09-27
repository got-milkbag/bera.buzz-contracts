// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBexPriceDecoder {
    function getPrice() external view returns (uint256);
}
