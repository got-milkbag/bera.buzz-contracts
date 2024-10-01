// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./BuzzVault.sol";

/// @title BuzzVaultExponential contract
/// @notice A contract implementing an exponential bonding curve
contract BuzzVaultExponential is BuzzVault {
    using SafeERC20 for IERC20;
    /**
     * @notice Constructor for a new BuzzVaultExponential contract
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
     * @notice Quote the amount of tokens that can be bought or sold at the current curve
     * @param token The token address
     * @param amount The amount of tokens or Bera
     * @param isBuyOrder True if buying, false if selling
     * @return The amount of tokens or Bera that can be bought or sold
     * @return The price per token, scaled by 1e18
     */
    function quote(
        address token, 
        uint256 amount, 
        bool isBuyOrder
    ) external view override returns (uint256, uint256) {
        TokenInfo storage info = tokenInfo[token];
        if (info.bexListed) revert BuzzVault_BexListed();

        uint256 tokenBalance = info.tokenBalance;
        uint256 beraBalance = info.beraBalance;
        if (tokenBalance == 0 && beraBalance == 0) revert BuzzVault_UnknownToken();

        uint256 totalSupply = info.totalSupply;

        if (isBuyOrder) {
            return _calculateBuyPrice(amount, beraBalance, tokenBalance, totalSupply);
        } else {
            return _calculateSellPrice(amount, tokenBalance, beraBalance);
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
        uint256 beraAmount = msg.value;
        uint256 beraAmountPrFee = (beraAmount * PROTOCOL_FEE_BPS) / 10000;
        uint256 beraAmountAfFee = 0;

        if (affiliate != address(0)) {
            uint256 bps = _getBpsToDeductForReferrals(msg.sender);
            beraAmountAfFee = (beraAmount * bps) / 10000;
        }

        uint256 netBeraAmount = beraAmount - beraAmountPrFee - beraAmountAfFee;
        (uint256 tokenAmountBuy, ) = _calculateBuyPrice(netBeraAmount, info.beraBalance, info.tokenBalance, info.totalSupply);
        if (tokenAmountBuy < MIN_TOKEN_AMOUNT) revert BuzzVault_InvalidMinTokenAmount();
        if (tokenAmountBuy < minTokens) revert BuzzVault_SlippageExceeded();

        // Update balances
        info.beraBalance += netBeraAmount;
        info.tokenBalance -= tokenAmountBuy;

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
        (uint256 beraAmountSell, ) = _calculateSellPrice(tokenAmount, info.tokenBalance, info.beraBalance);

        if (address(this).balance < beraAmountSell) revert BuzzVault_InvalidReserves();
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

        netBeraAmount = beraAmountSell - beraAmountPrFee - beraAmountAfFee;

        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);

        _transferFee(feeRecipient, beraAmountPrFee);

        if (affiliate != address(0)) _forwardReferralFee(msg.sender, beraAmountAfFee);

        _transferFee(payable(msg.sender), netBeraAmount);
    }

    /**
     * @notice Calculate the amount of tokens that can be bought at the current curve
     * @param beraAmountIn The amount of Bera to buy with
     * @param beraBalance The Bera balance of the token
     * @param tokenBalance The token balance of the token
     * @param totalSupply The total supply of the token
     * @return amountOut The amount of tokens that will be bought
     * @return pricePerToken The price per token, scalend by 1e18
     */
    function _calculateBuyPrice(
        uint256 beraAmountIn,
        uint256 beraBalance,
        uint256 tokenBalance,
        uint256 totalSupply
    ) internal pure returns (uint256 amountOut, uint256 pricePerToken) {
        if (beraAmountIn == 0) revert BuzzVault_QuoteAmountZero();

        // Exponential price calculation (tokens = beraBalance + beraAmountIn)^2 / tokenBalance
        amountOut = ((beraBalance + beraAmountIn) ** 2) / tokenBalance;
        uint256 newSupply = tokenBalance - amountOut;
        if (newSupply > totalSupply) revert BuzzVault_InvalidReserves();
        
        pricePerToken = ((beraAmountIn * 1e18) / amountOut);
    }

    /**
     * @notice Calculate the amount of Bera that can be received for selling tokens
     * @param tokenAmountIn The amount of tokens to sell
     * @param tokenBalance The token balance of the token
     * @param beraBalance The Bera balance of the token
     * @return amountOut The amount of Bera that will be received
     * @return pricePerToken The price per token, scalend by 1e18
     */
    function _calculateSellPrice(
        uint256 tokenAmountIn,
        uint256 tokenBalance,
        uint256 beraBalance
    ) internal pure returns (uint256 amountOut, uint256 pricePerToken) {
        if (tokenAmountIn == 0) revert BuzzVault_QuoteAmountZero();

        // Calculate sell price using inverse exponential curve
        uint256 newTokenBalance = tokenBalance + tokenAmountIn;
        amountOut = beraBalance - (newTokenBalance ** 2 / tokenBalance);
        pricePerToken = ((amountOut * 1e18) / tokenAmountIn);
    }
}
