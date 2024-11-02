// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./BuzzVault.sol";
import "./libraries/Math.sol";

/// @title BuzzVaultLinear contract
/// @notice A contract implementing a linear bonding curve with a fixed slope
contract BuzzVaultLinear is BuzzVault {
    using SafeERC20 for IERC20;

    /**
     * @notice Constructor for a new BuzzVaultLinear contract
     * @param _feeRecipient The address that receives the protocol fee
     * @param _factory The factory contract that can register tokens
     * @param _referralManager The referral manager contract
     * @param _priceDecoder The price decoder contract
     * @param _liquidityManager The liquidity manager contract
     */
    constructor(
        address payable _feeRecipient,
        address _factory,
        address _referralManager,
        address _priceDecoder,
        address _liquidityManager
    ) BuzzVault(_feeRecipient, _factory, _referralManager, _priceDecoder, _liquidityManager) {}

    /**
     * @notice Quote the amount of tokens that will be bought or sold at the current curve
     * @param token The token address
     * @param amount The amount of tokens or Bera
     * @param isBuyOrder True if buying tokens, false if selling tokens
     * @return amountOut The amount of tokens or Bera that will be bought or sold
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

        uint256 totalSupply = TOTAL_MINTED_SUPPLY;

        if (isBuyOrder) {
            (amountOut, pricePerToken, pricePerBera) = _calculateBuyPrice(amount, tokenBalance, beraBalance, totalSupply);
        } else {
            (amountOut, pricePerToken, pricePerBera) = _calculateSellPrice(amount, tokenBalance, beraBalance, totalSupply);
        }
    }

    /**
     * @notice Buy tokens from the bonding curve with Bera
     * @param token The token address
     * @param minTokens The minimum amount of tokens to buy
     * @param info The token info struct
     * @return tokenAmount The amount of tokens bought
     */
    function _buy(address token, uint256 minTokens, TokenInfo storage info) internal override returns (uint256 tokenAmount) {
        uint256 beraAmount = msg.value;
        uint256 beraAmountPrFee = (beraAmount * PROTOCOL_FEE_BPS) / 10000;
        uint256 beraAmountAfFee;

        uint256 bps = _getBpsToDeductForReferrals(msg.sender);
        if (bps > 0) {
            beraAmountAfFee = (beraAmountPrFee * bps) / 10000;
            beraAmountPrFee -= beraAmountAfFee;
        }

        uint256 netBeraAmount = beraAmount - beraAmountPrFee - beraAmountAfFee;

        (uint256 tokenAmountBuy, uint256 beraPerToken, uint256 tokenPerBera) = _calculateBuyPrice(
            netBeraAmount,
            info.tokenBalance,
            info.beraBalance,
            TOTAL_MINTED_SUPPLY
        );
        if (tokenAmountBuy < MIN_TOKEN_AMOUNT) revert BuzzVault_InvalidMinTokenAmount();
        if (tokenAmountBuy < minTokens) revert BuzzVault_SlippageExceeded();

        // Update balances
        info.beraBalance += netBeraAmount;
        info.tokenBalance -= tokenAmountBuy;

        // Update prices
        info.lastPrice = beraPerToken;
        info.lastBeraPrice = tokenPerBera;

        _transferFee(feeRecipient, beraAmountPrFee);

        if (beraAmountAfFee > 0) _forwardReferralFee(msg.sender, beraAmountAfFee);

        IERC20(token).safeTransfer(msg.sender, tokenAmountBuy);

        tokenAmount = tokenAmountBuy;
    }

    /**
     * @notice Sell tokens to the bonding curve for Bera
     * @param token The token address
     * @param tokenAmount The amount of tokens to sell
     * @param minBera The minimum amount of Bera to receive
     * @param info The token info struct
     * @return netBeraAmount The amount of Bera after fees
     */
    function _sell(address token, uint256 tokenAmount, uint256 minBera, TokenInfo storage info) internal override returns (uint256 netBeraAmount) {
        (uint256 beraAmountSell, uint256 beraPerToken, uint256 tokenPerBera) = _calculateSellPrice(
            tokenAmount,
            info.tokenBalance,
            info.beraBalance,
            TOTAL_MINTED_SUPPLY
        );
        if (info.beraBalance < beraAmountSell) revert BuzzVault_InvalidReserves();
        if (beraAmountSell < minBera) revert BuzzVault_SlippageExceeded();
        if (beraAmountSell == 0) revert BuzzVault_QuoteAmountZero();

        uint256 beraAmountPrFee = (beraAmountSell * PROTOCOL_FEE_BPS) / 10000;
        uint256 beraAmountAfFee = 0;

        uint256 bps = _getBpsToDeductForReferrals(msg.sender);
        if (bps > 0) {
            beraAmountAfFee = (beraAmountPrFee * bps) / 10000;
            beraAmountPrFee -= beraAmountAfFee;
        }

        netBeraAmount = beraAmountSell - beraAmountPrFee - beraAmountAfFee;

        // Update balances
        info.beraBalance -= beraAmountSell;
        info.tokenBalance += tokenAmount;

        // Update prices
        info.lastPrice = beraPerToken;
        info.lastBeraPrice = tokenPerBera;

        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);

        _transferFee(feeRecipient, beraAmountPrFee);

        if (beraAmountAfFee > 0) _forwardReferralFee(msg.sender, beraAmountAfFee);

        _transferFee(payable(msg.sender), netBeraAmount);
    }

    /**
     * @notice Calculate the price to buy tokens
     * @dev Does not account for protocol or referral fees
     * @param beraAmountIn The amount of Bera to buy tokens with
     * @param tokenBalance The balance of tokens in the vault
     * @param beraBalance The balance of Bera in the vault
     * @param totalSupply The total supply of tokens
     * @return amountOut The amount of tokens that will be bought
     * @return pricePerToken The price per token, scalend by 1e18
     * @return pricePerBera The price per Bera, scaled by 1e18
     */
    function _calculateBuyPrice(
        uint256 beraAmountIn,
        uint256 tokenBalance,
        uint256 beraBalance,
        uint256 totalSupply
    ) internal pure returns (uint256 amountOut, uint256 pricePerToken, uint256 pricePerBera) {
        if (beraAmountIn == 0) revert BuzzVault_QuoteAmountZero();

        uint256 newSupply = Math.floorSqrt(2 * 1e24 * (beraAmountIn + beraBalance));
        if (newSupply > totalSupply) revert BuzzVault_InvalidReserves();

        amountOut = newSupply - (totalSupply - tokenBalance);
        pricePerToken = (beraAmountIn * 1e18) / amountOut;
        pricePerBera = (amountOut * 1e18) / beraAmountIn;
    }

    /**
     * @notice Calculate the price to sell tokens
     * @dev Does not account for protocol or referral fees
     * @param tokenAmountIn The amount of tokens to sell
     * @param tokenBalance The balance of tokens in the vault
     * @param beraBalance The balance of Bera in the vault
     * @param totalSupply The total supply of tokens
     * @return amountOut The amount of Bera that will be received
     * @return pricePerToken The price per token, scaled by 1e18
     * @return pricePerBera The price per Bera, scaled by 1e18
     */
    function _calculateSellPrice(
        uint256 tokenAmountIn,
        uint256 tokenBalance,
        uint256 beraBalance,
        uint256 totalSupply
    ) internal pure returns (uint256 amountOut, uint256 pricePerToken, uint256 pricePerBera) {
        if (tokenAmountIn == 0) revert BuzzVault_QuoteAmountZero();
        uint256 newTokenSupply = totalSupply - tokenBalance - tokenAmountIn;

        amountOut = beraBalance - (newTokenSupply ** 2 / (2 * 1e24));
        pricePerToken = (amountOut * 1e18) / tokenAmountIn;
        pricePerBera = (tokenAmountIn * 1e18) / amountOut;
    }
}
