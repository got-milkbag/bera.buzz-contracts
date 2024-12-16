// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {BuzzVaultExponential} from "../BuzzVaultExponential.sol";

// Mocked version to expose internal functions for testing
contract BuzzVaultExponentialMock is BuzzVaultExponential {
    constructor(
        address _feeManager,
        address _factory,
        address _referralManager,
        address _priceDecoder,
        address _liquidityManager,
        address _wbera
    ) BuzzVaultExponential(_feeManager, _factory, _referralManager, _priceDecoder, _liquidityManager, _wbera) {}

    function calculateSellPrice_(
        uint256 quoteBalance,
        uint256 quoteAmountIn,
        uint256 k,
        uint256 growthFactor
    ) external pure returns (uint256 amountOut, uint256 pricePerToken, uint256 pricePerBase) {
        return _calculateSellPrice(quoteBalance, quoteAmountIn, k, growthFactor);
    }

    function calculateBuyPrice_(
        uint256 baseBalance,
        uint256 baseAmountIn,
        uint256 k,
        uint256 growthFactor
    ) external pure returns (uint256 amountOut, uint256 pricePerToken, uint256 pricePerBase) {
        return _calculateBuyPrice(baseBalance, baseAmountIn, k, growthFactor);
    }
}
