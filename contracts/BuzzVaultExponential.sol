// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";

import "./BuzzVault.sol";
import "./interfaces/IBuzzToken.sol";

/// @title BuzzVaultExponential contract
/// @notice A contract implementing an exponential bonding curve
contract BuzzVaultExponential is BuzzVault {
    using SafeERC20 for IERC20;

    /**
     * @notice Constructor for a new BuzzVaultExponential contract
     * @param _feeManager The address of the fee manager contract collecting fees
     * @param _factory The factory contract that can register tokens
     * @param _referralManager The referral manager contract
     * @param _priceDecoder The price decoder contract
     * @param _liquidityManager The liquidity manager contract
     */
    constructor(
        address _feeManager,
        address _factory,
        address _referralManager,
        address _priceDecoder,
        address _liquidityManager,
        address _wbera
    ) BuzzVault(_feeManager, _factory, _referralManager, _priceDecoder, _liquidityManager, _wbera) {}

    /**
     * @notice Quote the amount of tokens that can be bought or sold at the current curve
     * @param token The quote token address
     * @param amount The amount of base tokens is isBuyOrder is true, or the amount of quote tokens if isBuyOrder is false
     * @param isBuyOrder True if buying, false if selling
     * @return amountOut The amount of base or quote tokens that can be bought or sold
     * @return pricePerToken The price per quote token, scaled by 1e18
     * @return pricePerBase The price per base token, scaled by 1e18
     */
    function quote(
        address token,
        uint256 amount,
        bool isBuyOrder
    ) external view override returns (uint256 amountOut, uint256 pricePerToken, uint256 pricePerBase) {
        TokenInfo storage info = tokenInfo[token];
        if (info.bexListed) revert BuzzVault_BexListed();

        uint256 tokenBalance = info.tokenBalance;
        uint256 baseBalance = info.baseBalance;
        uint256 k = info.k;
        uint256 growthRate = info.growthRate;

        if (tokenBalance == 0 && baseBalance == 0) revert BuzzVault_UnknownToken();

        uint256 circulatingSupply = TOTAL_MINTED_SUPPLY - tokenBalance;

        if (isBuyOrder) {
            uint256 amountAfterFee = amount - feeManager.quoteTradingFee(amount);
            (amountOut, pricePerToken, pricePerBase) = _calculateBuyPrice(baseBalance, amountAfterFee, k, growthRate);
            if (amountOut > tokenBalance) revert BuzzVault_InvalidReserves();
        } else {
            (amountOut, pricePerToken, pricePerBase) = _calculateSellPrice(circulatingSupply, amount, k, growthRate);
            amountOut -= feeManager.quoteTradingFee(amountOut);
        }
    }

    /**
     * @notice Buy tokens from the bonding curve
     * @param token The token address
     * @param baseAmount The base amount of tokens used to buy with
     * @param minTokensOut The minimum amount of tokens to buy
     * @param info The token info struct
     * @return tokenAmount The amount of tokens bought
     */
    function _buy(
        address token,
        uint256 baseAmount,
        uint256 minTokensOut,
        address recipient,
        TokenInfo storage info
    ) internal override returns (uint256 tokenAmount) {
        uint256 tradingFee = feeManager.quoteTradingFee(baseAmount);
        uint256 netBaseAmount = baseAmount - tradingFee;
        
        (uint256 tokenAmountBuy, uint256 basePerToken, uint256 tokenPerBase) = _calculateBuyPrice(
            info.baseBalance,
            netBaseAmount,
            info.k,
            info.growthRate
        );

        if (tokenAmountBuy < MIN_TOKEN_AMOUNT) revert BuzzVault_InvalidMinTokenAmount();
        if (tokenAmountBuy < minTokensOut) revert BuzzVault_SlippageExceeded();

        // Calculate base token surplus whenever applicable
        uint256 baseSurplus;
        if (tokenAmountBuy > info.tokenBalance || info.tokenBalance - tokenAmountBuy < MIN_TOKEN_AMOUNT) {
            tokenAmountBuy = info.tokenBalance;

            uint256 basePlusNet = info.baseBalance + netBaseAmount;
            if (basePlusNet > info.baseThreshold) {
                baseSurplus = basePlusNet - info.baseThreshold;
                netBaseAmount -= baseSurplus;
            }
        }

        // Update balances
        info.baseBalance += netBaseAmount;
        info.tokenBalance -= tokenAmountBuy;

        // Update prices
        info.lastPrice = basePerToken;
        info.lastBasePrice = tokenPerBase;
        info.currentPrice = (info.baseBalance * 1e18) / (info.tokenBalance + CURVE_BALANCE_THRESHOLD);
        info.currentBasePrice = ((info.tokenBalance + CURVE_BALANCE_THRESHOLD) * 1e18) / info.baseBalance;

        // Collect trading and referral fee
        _collectFees(info.baseToken, msg.sender, baseAmount);

        // Transfer tokens to the buyer
        IERC20(token).safeTransfer(recipient, tokenAmountBuy);

        // refund user if they paid too much
        if (baseSurplus > 0) {
            IERC20(info.baseToken).safeTransfer(msg.sender, baseSurplus);
        }

        tokenAmount = tokenAmountBuy;
    }

    /**
     * @notice Sell tokens to the bonding curve for base token
     * @param token The token address
     * @param tokenAmount The amount of tokens to sell
     * @param minAmountOut The minimum amount of base tokens to receive
     * @param info The token info struct
     * @param unwrap True if the base token should be unwrapped (only if base token in WBera)
     * @return netBaseAmount The amount of base tokens after fees
     */
    function _sell(
        address token,
        uint256 tokenAmount,
        uint256 minAmountOut,
        address recipient,
        TokenInfo storage info,
        bool unwrap
    ) internal override returns (uint256 netBaseAmount) {
        (uint256 baseAmountSell, uint256 basePerToken, uint256 tokenPerBase) = _calculateSellPrice(
            TOTAL_MINTED_SUPPLY - info.tokenBalance,
            tokenAmount,
            info.k,
            info.growthRate
        );

        if (info.baseBalance < baseAmountSell) revert BuzzVault_InvalidReserves();
        if (baseAmountSell < minAmountOut) revert BuzzVault_SlippageExceeded();
        if (baseAmountSell == 0) revert BuzzVault_QuoteAmountZero();

        // Update balances
        info.baseBalance -= baseAmountSell;
        info.tokenBalance += tokenAmount;

        // Update prices
        info.lastPrice = basePerToken;
        info.lastBasePrice = tokenPerBase;
        info.currentPrice = (info.baseBalance * 1e18) / (info.tokenBalance + CURVE_BALANCE_THRESHOLD);
        info.currentBasePrice = ((info.tokenBalance + CURVE_BALANCE_THRESHOLD) * 1e18) / info.baseBalance;

        uint256 tradingFee = feeManager.quoteTradingFee(baseAmountSell);

        netBaseAmount = baseAmountSell - tradingFee;

        // Collect trading and referral fee
        _collectFees(info.baseToken, msg.sender, baseAmountSell);

        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);

        if (unwrap && info.baseToken == address(wbera)) {
            _unwrap(recipient, netBaseAmount);
        } else {
            IERC20(info.baseToken).safeTransfer(recipient, netBaseAmount);
        }
    }

    /**
     * @notice Calculate the amount of quote tokens that can be bought at the current curve
     * @param baseRaised The amount of base tokens raised
     * @param baseAmountIn The amount of base tokens to buy with
     * @param k The k coefficient of the curve
     * @param growthFactor The growth coefficient of the curve
     * @return amountOut The amount of quote tokens that will be bought
     * @return pricePerToken The price per quote token, scalend by 1e18
     * @return pricePerBase The price per base token, scaled by 1e18
     */
    function _calculateBuyPrice(
        uint256 baseRaised,
        uint256 baseAmountIn,
        uint256 k,
        uint256 growthFactor
    ) internal pure returns (uint256 amountOut, uint256 pricePerToken, uint256 pricePerBase) {
        if (baseAmountIn == 0) revert BuzzVault_QuoteAmountZero();

        UD60x18 baseBalanceFixed = ud(baseRaised);
        UD60x18 baseAmountFixed = ud(baseAmountIn);
        UD60x18 kFixed = ud(k);
        UD60x18 growthFactorFixed = ud(growthFactor);

        // Calculate tokensBefore = ln((totalRaised / k) + 1) / growthRate
        UD60x18 tokensBefore = baseBalanceFixed.div(kFixed).add(ud(1e18)).ln().div(growthFactorFixed);

        // Calculate tokensAfter = ln(((totalRaised + baseAmount) / k) + 1) / growthRate
        UD60x18 tokensAfter = baseBalanceFixed.add(baseAmountFixed).div(kFixed).add(ud(1e18)).ln().div(growthFactorFixed);

        // Return the difference in tokens
        amountOut = tokensAfter.sub(tokensBefore).unwrap();
        pricePerToken = (baseAmountIn * 1e18) / amountOut;
        pricePerBase = (amountOut * 1e18) / baseAmountIn;
    }

    /**
     * @notice Calculate the amount of base tokens that can be received for selling quote tokens
     * @param quoteSold The amount of quote tokens sold
     * @param quoteAmountIn The amount of quote tokens to sell
     * @param k The k coefficient of the curve
     * @param growthFactor The growth coefficient of the curve
     * @return amountOut The amount of base tokens that will be received
     * @return pricePerToken The price per quote token, scalend by 1e18
     * @return pricePerBase The price per base token, scaled by 1e18
     */
    function _calculateSellPrice(
        uint256 quoteSold,
        uint256 quoteAmountIn,
        uint256 k,
        uint256 growthFactor
    ) internal pure returns (uint256 amountOut, uint256 pricePerToken, uint256 pricePerBase) {
        if (quoteAmountIn == 0) revert BuzzVault_QuoteAmountZero();
        if (quoteSold < quoteAmountIn) revert BuzzVault_InvalidReserves();

        UD60x18 quoteBalanceFixed = ud(quoteSold);
        UD60x18 quoteAmountFixed = ud(quoteAmountIn);
        UD60x18 kFixed = ud(k);
        UD60x18 growthFactorFixed = ud(growthFactor);

        // Calculate baseBefore = k * (exp(growthFactor * tokensSold) - 1)
        UD60x18 baseBefore = kFixed.mul(growthFactorFixed.mul(quoteBalanceFixed).exp()).sub(kFixed);

        // Calculate baseAfter = k * (exp(growthFactor * (tokensSold - tokenAmount)) - 1)
        UD60x18 baseAfter = kFixed.mul(growthFactorFixed.mul(quoteBalanceFixed.sub(quoteAmountFixed)).exp()).sub(kFixed);

        // Return the difference in Wei
        amountOut = baseBefore.sub(baseAfter).unwrap();
        pricePerToken = (amountOut * 1e18) / quoteAmountIn;
        pricePerBase = (quoteAmountIn * 1e18) / amountOut;
    }

    function _collectFees(address token, address user, uint256 amount) internal returns (uint256 tradingFee, uint256 referralFee) {
        tradingFee = feeManager.quoteTradingFee(amount);
        if (tradingFee > 0) {
            referralFee = referralManager.quoteReferralFee(user, tradingFee);
            uint256 tradingMinusRef = tradingFee - referralFee; // will never underflow because ref fee is a % of trading fee

            IERC20(token).safeApprove(address(feeManager), tradingMinusRef);
            feeManager.collectTradingFee(token, tradingMinusRef);
            _collectReferralFee(user, token, tradingFee);
        }
    }
}
