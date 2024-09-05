// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/Math.sol";

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
    address public referralManager;
    address payable public feeRecipient;

    struct TokenInfo {
        uint256 tokenBalance;
        uint256 beraBalance; // aka reserve balance
        uint256 totalSupply;
        bool bexListed;
    }

    mapping(address => TokenInfo) public tokenInfo;

    constructor(address _factory, address _referralManager) {
        factory = _factory;
        referralManager = _referralManager;
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

        _buy(token, minTokens, affiliate, info);
    }

    function sell(address token, uint256 tokenAmount, uint256 minBera, address affiliate) public nonReentrant {
        if (tokenAmount == 0) revert BuzzVault_InvalidAmount();

        TokenInfo storage info = tokenInfo[token];
        if (info.tokenBalance == 0 && info.beraBalance == 0) revert BuzzVault_UnknownToken();

        _sell(token, tokenAmount, minBera, affiliate, info);
    }

    function _buy(address token, uint256 minTokens, address affiliate, TokenInfo storage info) internal virtual;

    function _sell(address token, uint256 tokenAmount, uint256 minBera, address affiliate, TokenInfo storage info) internal virtual;

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

    function _transferFee(address payable recipient, uint256 amount) internal {
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) revert BuzzVault_FeeTransferFailed();
    }
}
