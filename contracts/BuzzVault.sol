// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BuzzVault is ReentrancyGuard {
    error BuzzVault_InvalidAmount();
    error BuzzVault_InvalidReserves();
    error BuzzVault_BexListed();
    error BuzzVault_UnknownToken();
    error BuzzVault_SlippageExceeded();
    error BuzzVault_FeeTransferFailed();
    error BuzzVault_Unauthorized();
    error BuzzVault_TokenExists();

    uint256 public protocolFeeBps; // eg 100
    uint256 public affeliateFeeBps; // eg 100

    uint256 public reserveTokens;
    uint256 public reserveBera;

    address public factory;
    address payable public feeRecipient;

    struct TokenInfo {
        uint256 tokenBalance;
        uint256 beraBalance;
        bool bexListed;
    }

    mapping(address => TokenInfo) public tokenInfo;

    constructor(address _factory) {
        factory = _factory;
    }

    function registerToken(address token, uint256 tokenBalance) public {
        if (msg.sender != factory) revert BuzzVault_Unauthorized();
        if (
            tokenInfo[token].tokenBalance == 0 &&
            tokenInfo[token].beraBalance == 0
        ) revert BuzzVault_TokenExists();
        IERC20(token).transferFrom(msg.sender, address(this), tokenBalance);
        tokenInfo[token] = TokenInfo(tokenBalance, 0, false);
    }

    function buy(
        address token,
        uint256 minTokens,
        address affiliate
    ) public payable nonReentrant {
        if (msg.value == 0) revert BuzzVault_InvalidAmount();

        TokenInfo storage info = tokenInfo[token];
        if (info.tokenBalance == 0 && info.beraBalance == 0)
            revert BuzzVault_UnknownToken();

        uint256 beraAmount = msg.value;
        uint256 beraAmountPrFee = (beraAmount * protocolFeeBps) / 10000;
        uint256 beraAmountAfFee = 0;
        if (affiliate != address(0)) {
            beraAmountAfFee = (beraAmount * affeliateFeeBps) / 10000;
        }

        uint256 netBeraAmount = beraAmount - beraAmountPrFee - beraAmountAfFee;

        // TOD: check if bera amount to be sold is available
        uint256 tokenAmount = _getAmountFromCurve(
            netBeraAmount,
            info.beraBalance,
            info.tokenBalance
        );
        if (tokenAmount < minTokens) revert BuzzVault_SlippageExceeded();
        // Update balances
        info.beraBalance += netBeraAmount;
        info.tokenBalance -= tokenAmount;

        // TODO - Implement Affiliate fee transfer
        _transferFee(feeRecipient, beraAmountPrFee);

        IERC20(token).transfer(msg.sender, tokenAmount);

        // TODO - Call Event Tracker

        // TODO - Check if needs to be listed to Bex
    }

    function sell(
        address token,
        uint256 tokenAmount,
        uint256 minBera,
        address affiliate
    ) public nonReentrant {
        if (tokenAmount == 0) revert BuzzVault_InvalidAmount();

        TokenInfo storage info = tokenInfo[token];
        if (info.tokenBalance == 0 && info.beraBalance == 0)
            revert BuzzVault_UnknownToken();

        // TOD: check if bera amount to be bought is available
        uint256 beraAmount = _getAmountFromCurve(
            tokenAmount,
            info.tokenBalance,
            info.beraBalance
        );

        uint256 beraAmountPrFee = (beraAmount * protocolFeeBps) / 10000;
        uint256 beraAmountAfFee = 0;
        if (affiliate != address(0)) {
            beraAmountAfFee = (beraAmount * affeliateFeeBps) / 10000;
        }

        uint256 netBeraAmount = beraAmount - beraAmountPrFee - beraAmountAfFee;

        if (beraAmount < minBera || beraAmount == 0)
            revert BuzzVault_SlippageExceeded();

        IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);

        // Update balances
        info.beraBalance -= beraAmount;
        info.tokenBalance += tokenAmount;

        // TODO - Implement Affiliate fee transfer
        _transferFee(feeRecipient, beraAmountPrFee);
        _transferFee(payable(msg.sender), netBeraAmount);

        // TODO - Call Event Tracker
    }

    function quote(
        address token,
        uint256 amount,
        bool isBuyOrder
    ) public view returns (uint256) {
        TokenInfo storage info = tokenInfo[token];
        if (info.tokenBalance == 0 && info.beraBalance == 0)
            revert BuzzVault_UnknownToken();
        if (info.bexListed) revert BuzzVault_BexListed();

        if (isBuyOrder) {
            return
                _getAmountFromCurve(
                    amount,
                    info.beraBalance,
                    info.tokenBalance
                );
        } else {
            return
                _getAmountFromCurve(
                    amount,
                    info.tokenBalance,
                    info.beraBalance
                );
        }
    }

    function _getAmountFromCurve(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256) {
        if (amountIn == 0) revert BuzzVault_InvalidAmount();
        if (reserveIn == 0 || reserveOut == 0)
            revert BuzzVault_InvalidReserves();
        return (amountIn * reserveOut) / (reserveIn + amountIn);
    }

    function _transferFee(address payable recipient, uint256 amount) internal {
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) revert BuzzVault_FeeTransferFailed();
    }
}
