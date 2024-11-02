// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "solady/src/utils/FixedPointMathLib.sol";

import "./BuzzVault.sol";

/// @title BuzzVaultExponential contract
/// @notice A contract implementing an exponential bonding curve
contract BuzzVaultExponential is BuzzVault {
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;

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
        if (tokenBalance == 0 && baseBalance == 0) revert BuzzVault_UnknownToken();

        uint256 circulatingSupply = TOTAL_SUPPLY_OF_TOKENS - tokenBalance;

        if (isBuyOrder) {
            (amountOut, pricePerToken, pricePerBase) = _calculateBuyPrice(circulatingSupply, amount, CURVE_ALPHA, CURVE_BETA);
            if (amountOut > tokenBalance) revert BuzzVault_InvalidReserves();
            //if (tokenBalance - amountOut < CURVE_BALANCE_THRESHOLD - (CURVE_BALANCE_THRESHOLD / 20)) revert BuzzVault_SoftcapReached();
        } else {
            (amountOut, pricePerToken, pricePerBase) = _calculateSellPrice(circulatingSupply, amount, CURVE_ALPHA, CURVE_BETA);
            if (amountOut > baseBalance) revert BuzzVault_InvalidReserves();
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
    function _buy(address token, uint256 baseAmount, uint256 minTokensOut, TokenInfo storage info) internal override returns (uint256 tokenAmount) {
        uint256 circulatingSupply = TOTAL_SUPPLY_OF_TOKENS - info.tokenBalance;

        // Collect trading and referral fee
        uint256 tradingFee = feeManager.quoteTradingFee(baseAmount);
        uint256 referralFee;
        if (tradingFee > 0) {
            referralFee = _collectReferralFee(msg.sender, info.baseToken, tradingFee);
            tradingFee -= referralFee; // will never underflow because ref fee is a % of trading fee
            IERC20(info.baseToken).approve(address(feeManager), tradingFee);
            feeManager.collectTradingFee(info.baseToken, tradingFee);
        }

        uint256 netBaseAmount = baseAmount - tradingFee - referralFee;
        (uint256 tokenAmountBuy, uint256 basePerToken, uint256 tokenPerBase) = _calculateBuyPrice(
            circulatingSupply,
            netBaseAmount,
            CURVE_ALPHA,
            CURVE_BETA
        );

        if (tokenAmountBuy < MIN_TOKEN_AMOUNT) revert BuzzVault_InvalidMinTokenAmount();
        if (tokenAmountBuy < minTokensOut) revert BuzzVault_SlippageExceeded();
        if (tokenAmountBuy > info.tokenBalance) revert BuzzVault_InvalidReserves();
        //if (info.tokenBalance - tokenAmountBuy < CURVE_BALANCE_THRESHOLD - (CURVE_BALANCE_THRESHOLD / 20)) revert BuzzVault_SoftcapReached();

        // Update balances
        info.baseBalance += netBaseAmount;
        info.tokenBalance -= tokenAmountBuy;

        // Update prices
        info.lastPrice = basePerToken;
        info.lastBasePrice = tokenPerBase;

        // Transfer tokens to the buyer
        IERC20(token).safeTransfer(msg.sender, tokenAmountBuy);

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
        TokenInfo storage info,
        bool unwrap
    ) internal override returns (uint256 netBaseAmount) {
        uint256 circulatingSupply = TOTAL_SUPPLY_OF_TOKENS - info.tokenBalance;
        (uint256 baseAmountSell, uint256 basePerToken, uint256 tokenPerBase) = _calculateSellPrice(
            circulatingSupply,
            tokenAmount,
            CURVE_ALPHA,
            CURVE_BETA
        );

        if (info.baseBalance < baseAmountSell) revert BuzzVault_InvalidReserves();
        if (baseAmountSell < minAmountOut) revert BuzzVault_SlippageExceeded();
        if (baseAmountSell == 0) revert BuzzVault_QuoteAmountZero();

        // Collect trading and referral fee
        uint256 tradingFee = feeManager.quoteTradingFee(baseAmountSell);
        uint256 referralFee;
        if (tradingFee > 0) {
            referralFee = _collectReferralFee(msg.sender, info.baseToken, tradingFee);
            tradingFee -= referralFee; // will never underflow because ref fee is a % of trading fee
            IERC20(info.baseToken).approve(address(feeManager), tradingFee);
            feeManager.collectTradingFee(info.baseToken, tradingFee);
        }

        // Update balances
        info.baseBalance -= baseAmountSell;
        info.tokenBalance += tokenAmount;

        // Update prices
        info.lastPrice = basePerToken;
        info.lastBasePrice = tokenPerBase;

        netBaseAmount = baseAmountSell - tradingFee - referralFee;

        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);

        if (unwrap) {
            uint256 balancePrior = address(this).balance;
            wbera.approve(address(wbera), netBaseAmount);
            wbera.withdraw(netBaseAmount);
            uint256 amount = address(this).balance - balancePrior;
            if (amount != netBaseAmount) revert BuzzVault_WBeraConversionFailed();
            _transferEther(payable(msg.sender), netBaseAmount);
        } else {
            IERC20(info.baseToken).safeTransfer(msg.sender, netBaseAmount);
        }
    }

    /**
     * @notice Calculate the amount of quote tokens that can be bought at the current curve
     * @param circulatingSupply The circulating supply of the quote token
     * @param baseAmountIn The amount of base tokens to buy with
     * @param curveAlpha The alpha coefficient of the curve
     * @param curveBeta The beta coefficient of the curve
     * @return amountOut The amount of quote tokens that will be bought
     * @return pricePerToken The price per quote token, scalend by 1e18
     * @return pricePerBase The price per base token, scaled by 1e18
     */
    function _calculateBuyPrice(
        uint256 circulatingSupply,
        uint256 baseAmountIn,
        uint256 curveAlpha,
        uint256 curveBeta
    ) internal pure returns (uint256 amountOut, uint256 pricePerToken, uint256 pricePerBase) {
        if (baseAmountIn == 0) revert BuzzVault_QuoteAmountZero();

        // calculate exp(b*x0)
        uint256 exp_b_x0 = uint256((int256(curveBeta.mulWad(circulatingSupply))).expWad());

        // calculate exp(b*x0) + (dy*b/a)
        uint256 exp_b_x1 = exp_b_x0 + baseAmountIn.fullMulDiv(curveBeta, curveAlpha);

        amountOut = uint256(int256(exp_b_x1).lnWad()).divWad(curveBeta) - circulatingSupply;
        pricePerToken = (baseAmountIn * 1e18) / amountOut;
        pricePerBase = (amountOut * 1e18) / baseAmountIn;
    }

    /**
     * @notice Calculate the amount of base tokens that can be received for selling quote tokens
     * @param circulatingSupply The circulating supply of the quote token
     * @param tokenAmountIn The amount of quote tokens to sell
     * @param curveAlpha The alpha coefficient of the curve
     * @param curveBeta The beta coefficient of the curve
     * @return amountOut The amount of base tokens that will be received
     * @return pricePerToken The price per quote token, scalend by 1e18
     * @return pricePerBase The price per base token, scaled by 1e18
     */
    function _calculateSellPrice(
        uint256 circulatingSupply,
        uint256 tokenAmountIn,
        uint256 curveAlpha,
        uint256 curveBeta
    ) internal pure returns (uint256 amountOut, uint256 pricePerToken, uint256 pricePerBase) {
        if (tokenAmountIn == 0) revert BuzzVault_QuoteAmountZero();

        require(circulatingSupply >= tokenAmountIn, "BuzzVaultExponential: Not enough tokens to sell");
        // calculate exp(b*x0), exp(b*x1)
        int256 exp_b_x0 = (int256(curveBeta.mulWad(circulatingSupply))).expWad();
        int256 exp_b_x1 = (int256(curveBeta.mulWad(circulatingSupply - tokenAmountIn))).expWad();

        // calculate deltaY = (a/b)*(exp(b*x0) - exp(b*x1))
        uint256 delta = uint256(exp_b_x0 - exp_b_x1);

        amountOut = curveAlpha.fullMulDiv(delta, curveBeta);
        pricePerToken = (amountOut * 1e18) / tokenAmountIn;
        pricePerBase = (tokenAmountIn * 1e18) / amountOut;
    }
}
