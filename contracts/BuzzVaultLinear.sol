// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./BuzzVault.sol";
import "hardhat/console.sol";

contract BuzzVaultLinear is BuzzVault {
    constructor(
        address payable _feeRecipient,
        address _factory,
        address _referralManager,
        address _eventTracker,
        address _priceDecoder
    ) BuzzVault(_feeRecipient, _factory, _referralManager, _eventTracker, _priceDecoder) {}

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

        // TOD: check if bera amount to be sold is available
        (uint256 tokenAmount, uint256 beraPerToken) = _calculateBuyPrice(netBeraAmount, info.tokenBalance, info.beraBalance, info.totalSupply);
        if (tokenAmount < minTokens) revert BuzzVault_SlippageExceeded();
        // Update balances
        info.beraBalance += netBeraAmount;
        info.tokenBalance -= tokenAmount;
        info.lastPrice = beraPerToken;

        _transferFee(feeRecipient, beraAmountPrFee);

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
        (uint256 beraAmount, uint256 beraPerToken) = _calculateSellPrice(tokenAmount, info.tokenBalance, info.beraBalance, info.totalSupply);

        uint256 beraAmountPrFee = (beraAmount * protocolFeeBps) / 10000;
        uint256 beraAmountAfFee = 0;
        if (affiliate != address(0)) {
            uint256 bps = _getBpsToDeductForReferrals(msg.sender);
            beraAmountAfFee = (beraAmount * bps) / 10000;
            _forwardReferralFee(msg.sender, beraAmountAfFee);
        }

        uint256 netBeraAmount = beraAmount - beraAmountPrFee - beraAmountAfFee;

        if (beraAmount < minBera || beraAmount == 0) revert BuzzVault_SlippageExceeded();

        IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);

        // Update balances
        info.beraBalance -= beraAmount;
        info.tokenBalance += tokenAmount;
        info.lastPrice = beraPerToken;

        _transferFee(feeRecipient, beraAmountPrFee);
        _transferFee(payable(msg.sender), netBeraAmount);
        return beraAmount;
    }

    // TODO - Improve implementation
    function quote(address token, uint256 amount, bool isBuyOrder) public view override returns (uint256, uint256) {
        TokenInfo storage info = tokenInfo[token];
        if (info.tokenBalance == 0 && info.beraBalance == 0) revert BuzzVault_UnknownToken();
        if (info.bexListed) revert BuzzVault_BexListed();

        if (isBuyOrder) {
            return _calculateBuyPrice(amount, info.tokenBalance, info.beraBalance, info.totalSupply);
        } else {
            return _calculateSellPrice(amount, info.tokenBalance, info.beraBalance, info.totalSupply);
        }
    }

    // use when buying tokens - returns the token amount that will be bought
    function _calculateBuyPrice(
        uint256 beraAmountIn,
        uint256 tokenBalance,
        uint256 beraBalance,
        uint256 totalSupply
    ) internal pure returns (uint256, uint256) {
        if (beraAmountIn == 0) revert BuzzVault_InvalidAmount();

        uint256 newSupply = Math.floorSqrt(2 * 1e24 * (beraAmountIn + beraBalance));
        uint256 amountOut = newSupply - (totalSupply - tokenBalance);
        if (newSupply > totalSupply) revert BuzzVault_InvalidReserves();

        // Get scaled price
        return (amountOut, (beraAmountIn * 1e18) / amountOut);
    }

    // use when selling tokens - returns the bera amount that will be sent to the user, without accounting for fees
    function _calculateSellPrice(
        uint256 tokenAmountIn,
        uint256 tokenBalance,
        uint256 beraBalance,
        uint256 totalSupply
    ) internal pure returns (uint256, uint256) {
        if (tokenAmountIn == 0) revert BuzzVault_InvalidAmount();
        uint256 newTokenSupply = totalSupply - tokenBalance - tokenAmountIn;

        uint256 amountOut = beraBalance - (newTokenSupply ** 2 / (2 * 1e24));
        return (amountOut, ((amountOut * 1e18) / tokenAmountIn));
    }
}
