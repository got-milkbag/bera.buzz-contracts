// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./BuzzVault.sol";

contract BuzzVaultLinear is BuzzVault {
    constructor(address _factory, address _referralManager) BuzzVault(_factory, _referralManager) {}

    function _buy(address token, uint256 minTokens, address affiliate, TokenInfo storage info) internal override {
        uint256 beraAmount = msg.value;
        uint256 beraAmountPrFee = (beraAmount * protocolFeeBps) / 10000;
        uint256 beraAmountAfFee = 0;
        if (affiliate != address(0)) {
            // TODO
        }

        uint256 netBeraAmount = beraAmount - beraAmountPrFee - beraAmountAfFee;

        // TOD: check if bera amount to be sold is available
        uint256 tokenAmount = _calculateBuyPrice(netBeraAmount, info.beraBalance, info.tokenBalance, info.totalSupply);
        if (tokenAmount < minTokens) revert BuzzVault_SlippageExceeded();
        // Update balances
        info.beraBalance += netBeraAmount;
        info.tokenBalance -= tokenAmount;

        _transferFee(feeRecipient, beraAmountPrFee);

        IERC20(token).transfer(msg.sender, tokenAmount);
    }

    function _sell(address token, uint256 tokenAmount, uint256 minBera, address affiliate, TokenInfo storage info) internal override {
        // TOD: check if bera amount to be bought is available
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
    }

    // TODO - Improve implementation
    function quote(address token, uint256 amount, bool isBuyOrder) public view override returns (uint256) {
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
    ) internal pure returns (uint256) {
        if (beraAmountIn == 0) revert BuzzVault_InvalidAmount();

        uint256 newSupply = Math.floorSqrt(2 * 1e18 * ((beraAmountIn) + beraBalance));
        uint256 amountOut = newSupply - (totalSupply - tokenBalance);
        if (newSupply > totalSupply) revert BuzzVault_InvalidReserves();

        return (amountOut);
    }

    // use when selling tokens - returns the bera amount that will be sent to the user
    function _calculateSellPrice(
        uint256 tokenAmountIn,
        uint256 tokenBalance,
        uint256 beraBalance,
        uint256 totalSupply
    ) internal pure returns (uint256) {
        if (tokenAmountIn == 0) revert BuzzVault_InvalidAmount();
        uint256 newTokenSupply = tokenBalance + tokenAmountIn;

        // Should be the same as: (1/2 * (totalSupply**2 - newTokenSupply**2);
        return beraBalance - (newTokenSupply ** 2 / (2 * 1e18));
    }
}
