// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {BuzzVaultExponential} from "../BuzzVaultExponential.sol";

// Mocked version to expose internal functions for testing
contract BuzzVaultExponentialMock is BuzzVaultExponential {
    constructor(
        address _feeManager,
        address _factory,
        address _referralManager,
        address _liquidityManager,
        address _wbera
    )
        BuzzVaultExponential(
            _feeManager,
            _factory,
            _referralManager,
            _liquidityManager,
            _wbera
        )
    {}

    function calculateSellPrice_(
        uint256 quoteAmountIn,
        uint256 quoteBalance,
        uint256 baseBalance
    ) external pure returns (uint256 amountOut) {
        return _calculateSellPrice(quoteAmountIn, quoteBalance, baseBalance);
    }
}
