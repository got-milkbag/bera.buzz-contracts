// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./BuzzVault.sol";

/// @title BuzzVaultLinear contract
/// @notice A contract implementing a linear bonding curve with a fixed slope
contract BuzzVaultLinear is BuzzVault {
    /**
     * @notice Constructor for a new BuzzVaultLinear contract
     * @param _feeRecipient The address that receives the protocol fee
     * @param _factory The factory contract that can register tokens
     * @param _referralManager The referral manager contract
     * @param _eventTracker The event tracker contract
     * @param _priceDecoder The price decoder contract
     */
    constructor(
        address payable _feeRecipient,
        address _factory,
        address _referralManager,
        address _eventTracker,
        address _priceDecoder
    ) BuzzVault(_feeRecipient, _factory, _referralManager, _eventTracker, _priceDecoder) {}

    /**
     * @notice Quote the amount of tokens that will be bought or sold at the current curve
     * @param token The token address
     * @param amount The amount of tokens or Bera
     * @param isBuyOrder True if buying tokens, false if selling tokens
     * @return The amount of tokens or Bera that will be bought or sold
     */
    function quote(address token, uint256 amount, bool isBuyOrder) external view override returns (uint256, uint256) {
        TokenInfo storage info = tokenInfo[token];
        if (info.bexListed) revert BuzzVault_BexListed();

        uint256 tokenBalance = info.tokenBalance;
        uint256 beraBalance = info.beraBalance;
        if (tokenBalance == 0 && beraBalance == 0) revert BuzzVault_UnknownToken();
        
        uint256 totalSupply = info.totalSupply;

        if (isBuyOrder) {
            return _calculateBuyPrice(amount, tokenBalance, beraBalance, totalSupply);
        } else {
            return _calculateSellPrice(amount, tokenBalance, beraBalance, totalSupply);
        }
    }

    /**
     * @notice Buy tokens from the bonding curve with Bera
     * @param token The token address
     * @param minTokens The minimum amount of tokens to buy
     * @param affiliate The affiliate address
     * @param info The token info struct
     */
    function _buy(address token, uint256 minTokens, address affiliate, TokenInfo storage info) internal override returns (uint256) {
        uint256 beraAmount = msg.value;
        uint256 beraAmountPrFee = (beraAmount * PROTOCOL_FEE_BPS) / 10000;
        uint256 beraAmountAfFee = 0;
        if (affiliate != address(0)) {
            uint256 bps = _getBpsToDeductForReferrals(msg.sender);
            beraAmountAfFee = (beraAmount * bps) / 10000;
        }

        uint256 netBeraAmount = beraAmount - beraAmountPrFee - beraAmountAfFee;

        (uint256 tokenAmount, uint256 beraPerToken) = _calculateBuyPrice(netBeraAmount, info.tokenBalance, info.beraBalance, info.totalSupply);
        if (tokenAmount < MIN_TOKEN_AMOUNT) revert BuzzVault_InvalidMinTokenAmount();
        if (tokenAmount < minTokens) revert BuzzVault_SlippageExceeded();
        // Update balances
        info.beraBalance += netBeraAmount;
        info.tokenBalance -= tokenAmount;
        info.lastPrice = beraPerToken;

        _transferFee(feeRecipient, beraAmountPrFee);

        if (affiliate != address(0)) _forwardReferralFee(msg.sender, beraAmountAfFee);

        IERC20(token).transfer(msg.sender, tokenAmount);
        return tokenAmount;
    }

    /**
     * @notice Sell tokens to the bonding curve for Bera
     * @param token The token address
     * @param tokenAmount The amount of tokens to sell
     * @param minBera The minimum amount of Bera to receive
     * @param affiliate The affiliate address
     * @param info The token info struct
     */
    function _sell(
        address token,
        uint256 tokenAmount,
        uint256 minBera,
        address affiliate,
        TokenInfo storage info
    ) internal override returns (uint256) {
        (uint256 beraAmount, uint256 beraPerToken) = _calculateSellPrice(tokenAmount, info.tokenBalance, info.beraBalance, info.totalSupply);
        if (address(this).balance < beraAmount) revert BuzzVault_InvalidReserves();
        if (beraAmount < minBera) revert BuzzVault_SlippageExceeded();
        if (beraAmount == 0) revert BuzzVault_QuoteAmountZero();

        uint256 beraAmountPrFee = (beraAmount * PROTOCOL_FEE_BPS) / 10000;
        uint256 beraAmountAfFee = 0;

        if (affiliate != address(0)) {
            uint256 bps = _getBpsToDeductForReferrals(msg.sender);
            beraAmountAfFee = (beraAmount * bps) / 10000;
        }

        uint256 netBeraAmount = beraAmount - beraAmountPrFee - beraAmountAfFee;

        // Update balances
        info.beraBalance -= beraAmount;
        info.tokenBalance += tokenAmount;
        info.lastPrice = beraPerToken;

        IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);

        _transferFee(feeRecipient, beraAmountPrFee);

        if (affiliate != address(0)) _forwardReferralFee(msg.sender, beraAmountAfFee);

        _transferFee(payable(msg.sender), netBeraAmount);

        return beraAmount;
    }

    /**
     * @notice Calculate the price to buy tokens
     * @dev Does not account for protocol or referral fees
     * @param beraAmountIn The amount of Bera to buy tokens with
     * @param tokenBalance The balance of tokens in the vault
     * @param beraBalance The balance of Bera in the vault
     * @param totalSupply The total supply of tokens
     * @return The amount of tokens that will be bought
     * @return The price per token, scalend by 1e18
     */
    function _calculateBuyPrice(
        uint256 beraAmountIn,
        uint256 tokenBalance,
        uint256 beraBalance,
        uint256 totalSupply
    ) internal pure returns (uint256, uint256) {
        if (beraAmountIn == 0) revert BuzzVault_QuoteAmountZero();

        uint256 newSupply = Math.floorSqrt(2 * 1e24 * (beraAmountIn + beraBalance));
        uint256 amountOut = newSupply - (totalSupply - tokenBalance);
        if (newSupply > totalSupply) revert BuzzVault_InvalidReserves();

        // Get scaled price
        return (amountOut, (beraAmountIn * 1e18) / amountOut);
    }

    /**
     * @notice Calculate the price to sell tokens
     * @dev Does not account for protocol or referral fees
     * @param tokenAmountIn The amount of tokens to sell
     * @param tokenBalance The balance of tokens in the vault
     * @param beraBalance The balance of Bera in the vault
     * @param totalSupply The total supply of tokens
     * @return The amount of Bera that will be received
     * @return The price per token, scaled by 1e18
     */
    function _calculateSellPrice(
        uint256 tokenAmountIn,
        uint256 tokenBalance,
        uint256 beraBalance,
        uint256 totalSupply
    ) internal pure returns (uint256, uint256) {
        if (tokenAmountIn == 0) revert BuzzVault_QuoteAmountZero();
        uint256 newTokenSupply = totalSupply - tokenBalance - tokenAmountIn;

        uint256 amountOut = beraBalance - (newTokenSupply ** 2 / (2 * 1e24));
        return (amountOut, ((amountOut * 1e18) / tokenAmountIn));
    }
}
