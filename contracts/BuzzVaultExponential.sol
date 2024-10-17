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
     * @param _feeRecipient The address that receives the protocol fee
     * @param _factory The factory contract that can register tokens
     * @param _referralManager The referral manager contract
     * @param _eventTracker The event tracker contract
     * @param _priceDecoder The price decoder contract
     * @param _liquidityManager The liquidity manager contract
     */
    constructor(
        address payable _feeRecipient,
        address _factory,
        address _referralManager,
        address _eventTracker,
        address _priceDecoder,
        address _liquidityManager
    ) BuzzVault(_feeRecipient, _factory, _referralManager, _eventTracker, _priceDecoder, _liquidityManager) {}

    /**
     * @notice Quote the amount of tokens that can be bought or sold at the current curve
     * @param token The token address
     * @param amount The amount of tokens or Bera
     * @param isBuyOrder True if buying, false if selling
     * @return amountOut The amount of tokens or Bera that can be bought or sold
     * @return pricePerToken The price per token, scaled by 1e18
     * @return pricePerBera The price per Bera, scaled by 1e18
     */
    function quote(
        address token, 
        uint256 amount, 
        bool isBuyOrder
    ) external view override returns (uint256 amountOut, uint256 pricePerToken, uint256 pricePerBera) {
        TokenInfo storage info = tokenInfo[token];
        if (info.bexListed) revert BuzzVault_BexListed();

        uint256 tokenBalance = info.tokenBalance;
        uint256 beraBalance = info.beraBalance;
        if (tokenBalance == 0 && beraBalance == 0) revert BuzzVault_UnknownToken();

        uint256 circulatingSupply = TOTAL_SUPPLY_OF_TOKENS - tokenBalance;

        if (isBuyOrder) {
            (amountOut, pricePerToken, pricePerBera) = _calculateBuyPrice(circulatingSupply, amount, SUPPLY_NO_DECIMALS, CURVE_COEFFICIENT);
        } else {
            (amountOut, pricePerToken, pricePerBera) = _calculateSellPrice(circulatingSupply, amount, SUPPLY_NO_DECIMALS, CURVE_COEFFICIENT);
        }
    }

    /**
     * @notice Buy tokens from the bonding curve with Bera
     * @param token The token address
     * @param minTokens The minimum amount of tokens to buy
     * @param affiliate The affiliate address
     * @param info The token info struct
     * @return tokenAmount The amount of tokens bought
     */
    function _buy(
        address token, 
        uint256 minTokens, 
        address affiliate, 
        TokenInfo storage info
    ) internal override returns (uint256 tokenAmount) {
        uint256 circulatingSupply = TOTAL_SUPPLY_OF_TOKENS - info.tokenBalance;
        uint256 beraAmount = msg.value;
        uint256 beraAmountPrFee = (beraAmount * PROTOCOL_FEE_BPS) / 10000;
        uint256 beraAmountAfFee;

        if (affiliate != address(0)) {
            uint256 bps = _getBpsToDeductForReferrals(msg.sender);
            beraAmountAfFee = (beraAmount * bps) / 10000;
        }

        uint256 netBeraAmount = beraAmount - beraAmountPrFee - beraAmountAfFee;
        (uint256 tokenAmountBuy, uint256 beraPerToken, uint256 tokenPerBera) = _calculateBuyPrice(circulatingSupply, netBeraAmount, SUPPLY_NO_DECIMALS, CURVE_COEFFICIENT);

        if (tokenAmountBuy < MIN_TOKEN_AMOUNT) revert BuzzVault_InvalidMinTokenAmount();
        if (tokenAmountBuy < minTokens) revert BuzzVault_SlippageExceeded();

        // Update balances
        info.beraBalance += netBeraAmount;
        info.tokenBalance -= tokenAmountBuy;

        // Update prices
        info.lastPrice = beraPerToken;
        info.lastBeraPrice = tokenPerBera;

        // Transfer the protocol fee
        _transferFee(feeRecipient, beraAmountPrFee);

        // Transfer the affiliate fee
        if (affiliate != address(0)) _forwardReferralFee(msg.sender, beraAmountAfFee);

        // Transfer tokens to the buyer
        IERC20(token).safeTransfer(msg.sender, tokenAmountBuy);

        tokenAmount = tokenAmountBuy;
    }

    /**
     * @notice Sell tokens to the bonding curve for Bera
     * @param token The token address
     * @param tokenAmount The amount of tokens to sell
     * @param minBera The minimum amount of Bera to receive
     * @param affiliate The affiliate address
     * @param info The token info struct
     * @return netBeraAmount The amount of Bera after fees
     */
    function _sell(
        address token,
        uint256 tokenAmount,
        uint256 minBera,
        address affiliate,
        TokenInfo storage info
    ) internal override returns (uint256 netBeraAmount) {
        uint256 circulatingSupply = TOTAL_SUPPLY_OF_TOKENS - info.tokenBalance;
        (uint256 beraAmountSell, uint256 beraPerToken, uint256 tokenPerBera) = _calculateSellPrice(circulatingSupply, tokenAmount, SUPPLY_NO_DECIMALS, CURVE_COEFFICIENT);

        if (info.beraBalance - INITIAL_VIRTUAL_BERA < beraAmountSell) revert BuzzVault_InvalidReserves();
        if (beraAmountSell < minBera) revert BuzzVault_SlippageExceeded();
        if (beraAmountSell == 0) revert BuzzVault_QuoteAmountZero();

        uint256 beraAmountPrFee = (beraAmountSell * PROTOCOL_FEE_BPS) / 10000;
        uint256 beraAmountAfFee = 0;

        if (affiliate != address(0)) {
            uint256 bps = _getBpsToDeductForReferrals(msg.sender);
            beraAmountAfFee = (beraAmountSell * bps) / 10000;
        }

        // Update balances
        info.beraBalance -= beraAmountSell;
        info.tokenBalance += tokenAmount;

        // Update prices
        info.lastPrice = beraPerToken;
        info.lastBeraPrice = tokenPerBera;

        netBeraAmount = beraAmountSell - beraAmountPrFee - beraAmountAfFee;

        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);

        _transferFee(feeRecipient, beraAmountPrFee);

        if (affiliate != address(0)) _forwardReferralFee(msg.sender, beraAmountAfFee);

        _transferFee(payable(msg.sender), netBeraAmount);
    }

    /**
     * @notice Calculate the amount of tokens that can be bought at the current curve
     * @param circulatingSupply The circulating supply of the token
     * @param beraAmountIn The amount of Bera to buy with
     * @param totalSupplyNoPrecision The total supply of the token without decimals
     * @param coefficient The coefficient of the curve
     * @return amountOut The amount of tokens that will be bought
     * @return pricePerToken The price per token, scalend by 1e18
     * @return pricePerBera The price per Bera, scaled by 1e18
     */
    function _calculateBuyPrice(
        uint256 circulatingSupply,
        uint256 beraAmountIn,
        uint256 totalSupplyNoPrecision,
        uint256 coefficient
    ) internal pure returns (uint256 amountOut, uint256 pricePerToken, uint256 pricePerBera) {
        if (beraAmountIn == 0) revert BuzzVault_QuoteAmountZero();

        // calculate exp(b*x0)
        uint256 exp_b_x0 = uint256((int256(totalSupplyNoPrecision.mulWad(circulatingSupply))).expWad());

        // calculate exp(b*x0) + (dy*b/a)
        uint256 exp_b_x1 = exp_b_x0 + beraAmountIn.fullMulDiv(totalSupplyNoPrecision, coefficient);

        amountOut = uint256(int256(exp_b_x1).lnWad()).divWad(totalSupplyNoPrecision) - circulatingSupply;
        pricePerToken = (beraAmountIn * 1e18) / amountOut;
        pricePerBera = (amountOut * 1e18) / beraAmountIn;
    }

    /**
     * @notice Calculate the amount of Bera that can be received for selling tokens
     * @param circulatingSupply The circulating supply of the token
     * @param tokenAmountIn The amount of tokens to sell
     * @param totalSupplyNoPrecision, The total supply of the token without decimals
     * @param coefficient The coefficient of the curve
     * @return amountOut The amount of Bera that will be received
     * @return pricePerToken The price per token, scalend by 1e18
     * @return pricePerBera The price per Bera, scaled by 1e18
     */
    function _calculateSellPrice(
        uint256 circulatingSupply,
        uint256 tokenAmountIn,
        uint256 totalSupplyNoPrecision,
        uint256 coefficient
    ) internal pure returns (uint256 amountOut, uint256 pricePerToken, uint256 pricePerBera) {
        if (tokenAmountIn == 0) revert BuzzVault_QuoteAmountZero();

        require(circulatingSupply >= tokenAmountIn, "BuzzVaultExponential: Not enough tokens to sell");
        // calculate exp(b*x0), exp(b*x1)
        int256 exp_b_x0 = (int256(totalSupplyNoPrecision.mulWad(circulatingSupply))).expWad();
        int256 exp_b_x1 = (int256(totalSupplyNoPrecision.mulWad(circulatingSupply - tokenAmountIn))).expWad();

        // calculate deltaY = (a/b)*(exp(b*x0) - exp(b*x1))
        uint256 delta = uint256(exp_b_x0 - exp_b_x1);

        amountOut = coefficient.fullMulDiv(delta, totalSupplyNoPrecision);
        pricePerToken = (amountOut * 1e18) / tokenAmountIn;
        pricePerBera = (tokenAmountIn * 1e18) / amountOut;
    }
}
