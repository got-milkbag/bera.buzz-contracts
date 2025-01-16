// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BuzzVault, SafeERC20, IERC20} from "./BuzzVault.sol";

/**
 * @title BuzzVaultExponential contract
 * @notice A contract implementing an exponential bonding curve
 * @author nexusflip, 0xMitzie
 */
contract BuzzVaultExponential is BuzzVault {
    using SafeERC20 for IERC20;

    /**
     * @notice Constructor for a new BuzzVaultExponential contract
     * @param _feeManager The address of the fee manager contract collecting fees
     * @param _factory The factory contract that can register tokens
     * @param _referralManager The referral manager contract
     * @param _liquidityManager The liquidity manager contract
     * @param _wbera The address of the wrapped Bera token
     */
    constructor(
        address _feeManager,
        address _factory,
        address _referralManager,
        address _liquidityManager,
        address _wbera
    )
        BuzzVault(
            _feeManager,
            _factory,
            _referralManager,
            _liquidityManager,
            _wbera
        )
    {}

    /**
     * @notice Quote the amount of tokens that can be bought or sold at the current curve
     * @param token The quote token address
     * @param amount Base tokens is isBuyOrder is true, quote tokens if isBuyOrder is false
     * @param isBuyOrder True if buying, false if selling
     * @return amountOut The amount of base or quote tokens that can be bought or sold
     */
    function quote(
        address token,
        uint256 amount,
        bool isBuyOrder
    ) external view override returns (uint256 amountOut) {
        if (amount == 0) revert BuzzVault_QuoteAmountZero();
        if (token == address(0)) revert BuzzVault_AddressZeroToken();

        TokenInfo storage info = tokenInfo[token];
        if (info.bexListed) revert BuzzVault_BexListed();

        uint256 tokenBalance = info.tokenBalance;
        uint256 baseBalance = info.baseBalance;
        if (tokenBalance == 0 && baseBalance == 0)
            revert BuzzVault_UnknownToken();

        if (isBuyOrder) {
            uint256 amountAfterFee = amount -
                FEE_MANAGER.quoteTradingFee(amount);
            (amountOut, ) = _calculateBuyPrice(
                amountAfterFee,
                baseBalance,
                tokenBalance,
                info.quoteThreshold,
                info.k
            );
        } else {
            amountOut = _calculateSellPrice(
                amount,
                tokenBalance,
                baseBalance,
                info.k
            );
            if (amountOut > baseBalance - info.initialBase)
                amountOut = baseBalance - info.initialBase;
            amountOut -= FEE_MANAGER.quoteTradingFee(amountOut);
        }
    }

    /**
     * @notice Buy tokens from the bonding curve
     * @param token The token address
     * @param baseAmount The base amount of tokens used to buy with
     * @param minTokensOut The minimum amount of tokens to buy
     * @param info The token info struct
     * @param recipient The address to send the tokens to
     * @return tokenAmount The amount of tokens bought
     */
    function _buy(
        address token,
        uint256 baseAmount,
        uint256 minTokensOut,
        address recipient,
        TokenInfo storage info
    ) internal override returns (uint256 tokenAmount, bool needsMigration) {
        uint256 tradingFee = FEE_MANAGER.quoteTradingFee(baseAmount);
        uint256 netBaseAmount = baseAmount - tradingFee;
        uint256 baseBalance = info.baseBalance;
        (uint256 tokenAmountBuy, bool exceeded) = _calculateBuyPrice(
            netBaseAmount,
            baseBalance,
            info.tokenBalance,
            info.quoteThreshold,
            info.k
        );

        if (tokenAmountBuy == 0) revert BuzzVault_QuoteAmountZero();
        if (tokenAmountBuy < minTokensOut) revert BuzzVault_SlippageExceeded();

        uint256 baseSurplus;
        if (exceeded) {
            uint256 basePlusNet = baseBalance + netBaseAmount;
            uint256 baseThreshold = info.baseThreshold;
            if (basePlusNet > baseThreshold) {
                baseSurplus = basePlusNet - baseThreshold;
                netBaseAmount -= baseSurplus;
            }
        }

        // Update balances
        info.baseBalance += netBaseAmount;
        info.tokenBalance -= tokenAmountBuy;

        // Collect trading and referral fee
        _collectFees(info.baseToken, msg.sender, baseAmount);

        // Transfer tokens to the buyer
        IERC20(token).safeTransfer(recipient, tokenAmountBuy);

        // refund user if they paid too much
        if (baseSurplus > 0) {
            IERC20(info.baseToken).safeTransfer(recipient, baseSurplus);
        }

        (tokenAmount, needsMigration) = (tokenAmountBuy, exceeded);
    }

    /**
     * @notice Sell tokens to the bonding curve for base token
     * @param token The token address
     * @param tokenAmount The amount of tokens to sell
     * @param minAmountOut The minimum amount of base tokens to receive
     * @param recipient The address to send the base tokens to
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
        address baseToken = info.baseToken;
        uint256 baseBalance = info.baseBalance;
        uint256 baseAmountSell = _calculateSellPrice(
            tokenAmount,
            info.tokenBalance,
            baseBalance,
            info.k      
        ); 

        uint256 baseSurplus = baseBalance - info.initialBase;
        if (baseAmountSell == 0) revert BuzzVault_QuoteAmountZero();
        if (baseAmountSell > baseSurplus) baseAmountSell = baseSurplus;
        if (baseAmountSell < minAmountOut) revert BuzzVault_SlippageExceeded();

        // Update balances
        info.baseBalance -= baseAmountSell;
        info.tokenBalance += tokenAmount;

        uint256 tradingFee = FEE_MANAGER.quoteTradingFee(baseAmountSell);

        netBaseAmount = baseAmountSell - tradingFee;

        // Collect trading and referral fee
        _collectFees(baseToken, msg.sender, baseAmountSell);

        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);

        if (unwrap && baseToken == address(WBERA)) {
            _unwrap(recipient, netBaseAmount);
        } else {
            IERC20(baseToken).safeTransfer(recipient, netBaseAmount);
        }
    }

    /**
     * @notice Calculate the amount of quote tokens that can be bought at the current curve
     * @param baseAmountIn The amount of base tokens to buy with
     * @param baseBalance The virtual base token balance in the curve
     * @param quoteBalance The virtual quote token balance in the curve
     * @param k The k coefficient of the curve
     * @return amountOut The amount of quote tokens that will be bought
     */
    function _calculateBuyPrice(
        uint256 baseAmountIn,
        uint256 baseBalance,
        uint256 quoteBalance,
        uint256 quoteThreshold,
        uint256 k
    ) internal pure returns (uint256 amountOut, bool exceeded) {
        uint256 amountAux = quoteBalance - k / (baseBalance + baseAmountIn);
        exceeded = amountAux >= quoteBalance - quoteThreshold;
        amountOut = exceeded ? quoteBalance - quoteThreshold : amountAux;
    }

    /**
     * @notice Calculate the amount of base tokens that can be received for selling quote tokens
     * @param quoteAmountIn The amount of quote tokens to sell
     * @param quoteBalance The virtual quote token balance in the curve
     * @param baseBalance The virtual base token balance in the curve
     * @param k The k coefficient of the curve
     * @return amountOut The amount of base tokens that will be received
     */
    function _calculateSellPrice(
        uint256 quoteAmountIn,
        uint256 quoteBalance,
        uint256 baseBalance,
        uint256 k
    ) internal pure returns (uint256 amountOut) {
        amountOut = baseBalance - k / (quoteBalance + quoteAmountIn);
    }

    /**
     * @notice Collect trading and referral fees
     * @param token The token address
     * @param user The user address
     * @param amount The amount of tokens to collect fees from
     * @return tradingFee The trading fee collected
     * @return referralFee The referral fee collected
     */
    function _collectFees(
        address token,
        address user,
        uint256 amount
    ) internal returns (uint256 tradingFee, uint256 referralFee) {
        tradingFee = FEE_MANAGER.quoteTradingFee(amount);
        if (tradingFee > 0) {
            referralFee = REFERRAL_MANAGER.quoteReferralFee(user, tradingFee);
            // will never underflow because ref fee is a % of trading fee
            uint256 tradingMinusRef = tradingFee - referralFee;

            IERC20(token).safeApprove(address(FEE_MANAGER), tradingMinusRef);
            FEE_MANAGER.collectTradingFee(token, tradingMinusRef);
            _collectReferralFee(user, token, tradingFee);
        }
    }
}
