// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.19;

interface ILPToken {
    function poolType() external view returns (uint256);

    function baseToken() external view returns (address);

    function quoteToken() external view returns (address);
}
