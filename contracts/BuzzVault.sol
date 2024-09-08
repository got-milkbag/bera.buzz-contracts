// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/Math.sol";
import "./interfaces/IReferralManager.sol";
import "./interfaces/IBuzzEventTracker.sol";

abstract contract BuzzVault is ReentrancyGuard {
    error BuzzVault_InvalidAmount();
    error BuzzVault_InvalidReserves();
    error BuzzVault_BexListed();
    error BuzzVault_UnknownToken();
    error BuzzVault_SlippageExceeded();
    error BuzzVault_FeeTransferFailed();
    error BuzzVault_Unauthorized();
    error BuzzVault_TokenExists();

    uint256 public constant protocolFeeBps = 100; // 100 -> 1%

    address public factory;
    address payable public feeRecipient;
    IReferralManager public referralManager;
    IBuzzEventTracker public eventTracker;

    struct TokenInfo {
        uint256 tokenBalance;
        uint256 beraBalance; // aka reserve balance
        uint256 totalSupply;
        bool bexListed;
    }

    mapping(address => TokenInfo) public tokenInfo;

    constructor(address payable _feeRecipient, address _factory, address _referralManager, address _eventTracker) {
        feeRecipient = _feeRecipient;
        factory = _factory;
        referralManager = IReferralManager(_referralManager);
        eventTracker = IBuzzEventTracker(_eventTracker);
    }

    function registerToken(address token, uint256 tokenBalance) public {
        if (msg.sender != factory) revert BuzzVault_Unauthorized();
        if (tokenInfo[token].tokenBalance != 0 && tokenInfo[token].beraBalance != 0) revert BuzzVault_TokenExists();
        IERC20(token).transferFrom(msg.sender, address(this), tokenBalance);
        // Assumption: Token has fixed supply upon deployment
        tokenInfo[token] = TokenInfo(tokenBalance, 0, IERC20(token).totalSupply(), false);
    }

    function buy(address token, uint256 minTokens, address affiliate) public payable nonReentrant {
        if (msg.value == 0) revert BuzzVault_InvalidAmount();

        TokenInfo storage info = tokenInfo[token];
        if (info.tokenBalance == 0 && info.beraBalance == 0) revert BuzzVault_UnknownToken();

        if (affiliate != address(0)) _setReferral(affiliate, msg.sender);

        uint256 amountBought = _buy(token, minTokens, affiliate, info);
        eventTracker.emitTrade(msg.sender, token, amountBought, msg.value, true);
    }

    function sell(address token, uint256 tokenAmount, uint256 minBera, address affiliate) public nonReentrant {
        if (tokenAmount == 0) revert BuzzVault_InvalidAmount();

        TokenInfo storage info = tokenInfo[token];
        if (info.tokenBalance == 0 && info.beraBalance == 0) revert BuzzVault_UnknownToken();

        if (affiliate != address(0)) _setReferral(affiliate, msg.sender);

        uint256 amountSold = _sell(token, tokenAmount, minBera, affiliate, info);
        eventTracker.emitTrade(msg.sender, token, tokenAmount, amountSold, false);
    }

    function _buy(address token, uint256 minTokens, address affiliate, TokenInfo storage info) internal virtual returns (uint256);

    function _sell(address token, uint256 tokenAmount, uint256 minBera, address affiliate, TokenInfo storage info) internal virtual returns (uint256);

    function quote(address token, uint256 amount, bool isBuyOrder) public view virtual returns (uint256);

    // // Get the last price of the token in terms of Bera
    // function getLastPrice(address token) public view returns (uint256) {
    //     TokenInfo storage info = tokenInfo[token];
    //     if (info.tokenBalance == 0 && info.beraBalance == 0) revert BuzzVault_UnknownToken();
    //     if (info.bexListed) revert BuzzVault_BexListed();
    //     // tokenBalance will always be greater than zero because the transfer to BEX will happen before that
    //     // Bera per token = (Reserve of Bera * 1e18) / Reserve of Token
    //     return (info.beraBalance * 1e18) / info.tokenBalance; // Returns with 18 decimal places precision
    // }

    function _setReferral(address referrer, address user) internal {
        referralManager.setReferral(referrer, user);
    }

    function _getBpsToDeductForReferrals(address user) internal view returns (uint256) {
        return referralManager.getReferreralBpsFor(user);
    }

    function _forwardReferralFee(address user, uint256 amount) internal {
        referralManager.receiveReferral{value: amount}(user);
    }

    function _transferFee(address payable recipient, uint256 amount) internal {
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) revert BuzzVault_FeeTransferFailed();
    }
}
