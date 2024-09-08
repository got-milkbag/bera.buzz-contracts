// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./BuzzVault.sol";

contract BuzzVaultExponential is BuzzVault {
    constructor(
        address payable _feeRecipient,
        address _factory,
        address _referralManager,
        address eventTracker
    ) BuzzVault(_feeRecipient, _factory, _referralManager, eventTracker) {}

    function _buy(address token, uint256 minTokens, address affiliate, TokenInfo storage info) internal override returns (uint256) {
        uint256 beraAmount = msg.value;
        uint256 beraAmountPrFee = (beraAmount * protocolFeeBps) / 10000;
        uint256 beraAmountAfFee = 0;
        if (affiliate != address(0)) {
            // TODO
        }

        uint256 netBeraAmount = beraAmount - beraAmountPrFee - beraAmountAfFee;

        uint256 tokenAmount = _calculateBuyPrice(netBeraAmount, info.beraBalance, info.tokenBalance, info.totalSupply);

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

    function _sell(
        address token,
        uint256 tokenAmount,
        uint256 minBera,
        address affiliate,
        TokenInfo storage info
    ) internal override returns (uint256) {
        // TODO: check if bera amount to be bought is available
        uint256 beraAmount = _calculateSellPrice(tokenAmount, info.tokenBalance, info.beraBalance, info.totalSupply);

        uint256 beraAmountPrFee = (beraAmount * protocolFeeBps) / 10000;
        uint256 beraAmountAfFee = 0;
        if (affiliate != address(0)) {
            // TODO
        }

        uint256 netBeraAmount = beraAmount - beraAmountPrFee - beraAmountAfFee;
        if (beraAmount < minBera || beraAmount == 0) revert BuzzVault_SlippageExceeded();

        IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);

        // Update balances
        info.beraBalance -= beraAmount;
        info.tokenBalance += tokenAmount;

        _transferFee(feeRecipient, beraAmountPrFee);
        _transferFee(payable(msg.sender), netBeraAmount);
        return beraAmount;
    }

    function quote(address token, uint256 amount, bool isBuyOrder) public view override returns (uint256) {
        TokenInfo storage info = tokenInfo[token];
        if (info.tokenBalance == 0 && info.beraBalance == 0) revert BuzzVault_UnknownToken();
        if (info.bexListed) revert BuzzVault_BexListed();

        if (isBuyOrder) {
            return _calculateBuyPrice(amount, info.beraBalance, info.tokenBalance, info.totalSupply);
        } else {
            return _calculateSellPrice(amount, info.tokenBalance, info.beraBalance, info.totalSupply);
        }
    }

    // Exponential curve logic for calculating token amount when buying
    function _calculateBuyPrice(
        uint256 beraAmountIn,
        uint256 beraBalance,
        uint256 tokenBalance,
        uint256 totalSupply
    ) internal pure returns (uint256) {
        if (beraAmountIn == 0) revert BuzzVault_InvalidAmount();

        // Exponential price calculation (tokens = beraBalance + beraAmountIn)^2 / tokenBalance
        uint256 newBeraBalance = beraBalance + beraAmountIn;
        uint256 tokenAmountOut = (newBeraBalance ** 2) / tokenBalance;
        uint256 newSupply = tokenBalance - tokenAmountOut;
        if (newSupply > totalSupply) revert BuzzVault_InvalidReserves();
        return (tokenAmountOut);
    }

    // Exponential curve logic for calculating Bera amount when selling
    function _calculateSellPrice(
        uint256 tokenAmountIn,
        uint256 tokenBalance,
        uint256 beraBalance,
        uint256 totalSupply
    ) internal pure returns (uint256) {
        if (tokenAmountIn == 0) revert BuzzVault_InvalidAmount();

        // Calculate sell price using inverse exponential curve
        uint256 newTokenBalance = tokenBalance + tokenAmountIn;
        uint256 beraAmount = beraBalance - (newTokenBalance ** 2 / tokenBalance);

        return beraAmount;
    }
}
