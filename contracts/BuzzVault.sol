// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/Math.sol";

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
        uint256 beraBalance; // aka reserve balance
        uint256 totalSupply;
        bool bexListed;
    }

    mapping(address => TokenInfo) public tokenInfo;

    constructor(address _factory) {
        factory = _factory;
    }

    function registerToken(address token, uint256 tokenBalance) public {
        if (msg.sender != factory) revert BuzzVault_Unauthorized();
        if (
            tokenInfo[token].tokenBalance != 0 &&
            tokenInfo[token].beraBalance != 0
        ) revert BuzzVault_TokenExists();
        IERC20(token).transferFrom(msg.sender, address(this), tokenBalance);
        // Assumption: Token has fixed supply upon deployment
        tokenInfo[token] = TokenInfo(
            tokenBalance,
            0,
            IERC20(token).totalSupply(),
            false
        );
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
        uint256 tokenAmount = _getTokenAmountOnCurve(
            netBeraAmount,
            info.beraBalance,
            info.tokenBalance,
            info.totalSupply
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
        uint256 beraAmount = _getBeraAmountOnCurve(
            tokenAmount,
            info.tokenBalance,
            info.beraBalance,
            info.totalSupply
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
                _getTokenAmountOnCurve(
                    amount,
                    info.tokenBalance,
                    info.beraBalance,
                    info.totalSupply
                );
        } else {
            return
                _getBeraAmountOnCurve(
                    amount,
                    info.tokenBalance,
                    info.beraBalance,
                    info.totalSupply
                );
        }
    }

    // use when buying tokens - returns the token amount that will be bought
    function _getTokenAmountOnCurve(
        uint256 beraAmountIn,
        uint256 tokenBalance,
        uint256 beraBalance,
        uint256 totalSupply
    ) internal pure returns (uint256) {
        if (beraAmountIn == 0) revert BuzzVault_InvalidAmount();

        uint256 newSupply = Math.floorSqrt(
            2 * 1e18 * ((beraAmountIn) + beraBalance)
        );

        uint256 amountOut = newSupply - (totalSupply - tokenBalance);
        if (newSupply > totalSupply) revert BuzzVault_InvalidReserves();

        return (amountOut);
    }

    // use when selling tokens - returns the bera amount that will be sent to the user
    function _getBeraAmountOnCurve(
        uint256 tokenAmountIn,
        uint256 tokenBalance,
        uint256 beraBalance,
        uint256 totalSupply
    ) internal pure returns (uint256) {
        if (tokenAmountIn == 0) revert BuzzVault_InvalidAmount();
        uint256 newTokenSupply = tokenBalance - tokenAmountIn;

        // Should be the same as: (1/2 * (totalSupply**2 - newTokenSupply**2);
        return beraBalance - (newTokenSupply ** 2 / (2 * 1e18));
    }

    function _transferFee(address payable recipient, uint256 amount) internal {
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) revert BuzzVault_FeeTransferFailed();
    }
}
