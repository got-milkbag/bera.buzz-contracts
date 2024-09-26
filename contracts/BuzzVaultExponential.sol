// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./BuzzVault.sol";

/// @title BuzzVaultExponential contract
/// @notice A contract implementing an exponential bonding curve
contract BuzzVaultExponential is BuzzVault {
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
     * @notice Buy tokens from the bonding curve with Bera
     * @param token The token address
     * @param minTokens The minimum amount of tokens to buy
     * @param affiliate The affiliate address
     * @param info The token info struct
     */
    function _buy(address token, uint256 minTokens, address affiliate, TokenInfo storage info) internal override returns (uint256) {
        uint256 beraAmount = msg.value;
        uint256 beraAmountPrFee = (beraAmount * protocolFeeBps) / 10000;
        uint256 beraAmountAfFee = 0;
        if (affiliate != address(0)) {
            uint256 bps = _getBpsToDeductForReferrals(msg.sender);
            beraAmountAfFee = (beraAmount * bps) / 10000;
            _forwardReferralFee(msg.sender, beraAmountAfFee);
        }

        uint256 netBeraAmount = beraAmount - beraAmountPrFee - beraAmountAfFee;

        (uint256 tokenAmount, ) = _calculateBuyPrice(netBeraAmount, info.beraBalance, info.tokenBalance, info.totalSupply);

        // TODO: check if bera amount to be sold is available
        if (tokenAmount < minTokens) revert BuzzVault_SlippageExceeded();

        // Update balances
        info.beraBalance += netBeraAmount;
        info.tokenBalance -= tokenAmount;

        // Transfer the protocol fee
        _transferFee(feeRecipient, beraAmountPrFee);

        // Transfer tokens to the buyer
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
        // TODO: check if bera amount to be bought is available
        (uint256 beraAmount, ) = _calculateSellPrice(tokenAmount, info.tokenBalance, info.beraBalance, info.totalSupply);

        uint256 beraAmountPrFee = (beraAmount * protocolFeeBps) / 10000;
        uint256 beraAmountAfFee = 0;
        if (affiliate != address(0)) {
            uint256 bps = _getBpsToDeductForReferrals(msg.sender);
            beraAmountAfFee = (beraAmount * bps) / 10000;
            _forwardReferralFee(msg.sender, beraAmountAfFee);
        }

        uint256 netBeraAmount = beraAmount - beraAmountPrFee - beraAmountAfFee;
        if (beraAmount < minBera || beraAmount == 0) revert BuzzVault_SlippageExceeded();

        // Update balances
        info.beraBalance -= beraAmount;
        info.tokenBalance += tokenAmount;

        IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);

        _transferFee(feeRecipient, beraAmountPrFee);
        _transferFee(payable(msg.sender), netBeraAmount);
        return beraAmount;
    }

    /**
     * @notice Quote the amount of tokens that can be bought or sold at the current curve
     * @param token The token address
     * @param amount The amount of tokens or Bera
     * @param isBuyOrder True if buying, false if selling
     * @return The amount of tokens or Bera that can be bought or sold
     */
    function quote(address token, uint256 amount, bool isBuyOrder) public view override returns (uint256, uint256) {
        TokenInfo storage info = tokenInfo[token];
        uint256 tokenBalance = info.tokenBalance;
        uint256 beraBalance = info.beraBalance;
        uint256 totalSupply = info.totalSupply;

        if (tokenBalance == 0 && beraBalance == 0) revert BuzzVault_UnknownToken();
        if (info.bexListed) revert BuzzVault_BexListed();

        if (isBuyOrder) {
            return _calculateBuyPrice(amount, beraBalance, tokenBalance, totalSupply);
        } else {
            return _calculateSellPrice(amount, tokenBalance, beraBalance, totalSupply);
        }
    }

    /**
     * @notice Calculate the amount of tokens that can be bought at the current curve
     * @param beraAmountIn The amount of Bera to buy with
     * @param beraBalance The Bera balance of the token
     * @param tokenBalance The token balance of the token
     * @param totalSupply The total supply of the token
     * @return The amount of tokens that will be bought
     * @return The price per token, scalend by 1e18
     */
    function _calculateBuyPrice(
        uint256 beraAmountIn,
        uint256 beraBalance,
        uint256 tokenBalance,
        uint256 totalSupply
    ) internal pure returns (uint256, uint256) {
        if (beraAmountIn == 0) revert BuzzVault_QuoteAmountZero();

        // Exponential price calculation (tokens = beraBalance + beraAmountIn)^2 / tokenBalance
        uint256 newBeraBalance = beraBalance + beraAmountIn;
        uint256 tokenAmountOut = (newBeraBalance ** 2) / tokenBalance;
        uint256 newSupply = tokenBalance - tokenAmountOut;
        if (newSupply > totalSupply) revert BuzzVault_InvalidReserves();
        return (tokenAmountOut, ((beraAmountIn * 1e18) / tokenAmountOut));
    }

    /**
     * @notice Calculate the amount of Bera that can be received for selling tokens
     * @param tokenAmountIn The amount of tokens to sell
     * @param tokenBalance The token balance of the token
     * @param beraBalance The Bera balance of the token
     * @param totalSupply The total supply of the token
     * @return The amount of Bera that will be received
     * @return The price per token, scalend by 1e18
     */
    function _calculateSellPrice(
        uint256 tokenAmountIn,
        uint256 tokenBalance,
        uint256 beraBalance,
        uint256 totalSupply
    ) internal pure returns (uint256, uint256) {
        if (tokenAmountIn == 0) revert BuzzVault_QuoteAmountZero();

        // Calculate sell price using inverse exponential curve
        uint256 newTokenBalance = tokenBalance + tokenAmountIn;
        uint256 beraAmount = beraBalance - (newTokenBalance ** 2 / tokenBalance);

        return (beraAmount, ((beraAmount * 1e18) / tokenAmountIn));
    }
}
