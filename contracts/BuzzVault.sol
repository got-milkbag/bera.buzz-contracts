// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./libraries/Math.sol";

import "./interfaces/IBexPriceDecoder.sol";
import "./interfaces/IBuzzEventTracker.sol";
import "./interfaces/IBexLiquidityManager.sol";
import "./interfaces/IReferralManager.sol";

/// @title BuzzVault contract
/// @notice An abstract contract holding logic for bonding curve operations, leaving the implementation of the curve to child contracts
abstract contract BuzzVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Error code emitted when the quote amount in buy/sell is zero
    error BuzzVault_QuoteAmountZero();
    /// @notice Error code emitted when the reserves are invalid
    error BuzzVault_InvalidReserves();
    /// @notice Error code emitted when user balance is invalid
    error BuzzVault_InvalidUserBalance();
    /// @notice Error code emitted when the token is not listed in Bex
    error BuzzVault_BexListed();
    /// @notice Error code emitted when the token is tracked in the curve
    error BuzzVault_UnknownToken();
    /// @notice Error code emitted when the slippage is exceeded
    error BuzzVault_SlippageExceeded();
    /// @notice Error code emitted when the fee transfer fails
    error BuzzVault_FeeTransferFailed();
    /// @notice Error code emitted when the caller is not authorized
    error BuzzVault_Unauthorized();
    /// @notice Error code emitted when the token already exists
    error BuzzVault_TokenExists();
    /// @notice Error code emitted when min ERC20 amount not respected
    error BuzzVault_InvalidMinTokenAmount();

    /// @notice The protocol fee in basis points
    uint256 public constant PROTOCOL_FEE_BPS = 100; // 100 -> 1%
    /// @notice The DEX migration fee in basis points
    uint256 public constant DEX_MIGRATION_FEE_BPS = 500; // 500 -> 5%
    /// @notice The min ERC20 amount for bonding curve swaps
    uint256 public constant MIN_TOKEN_AMOUNT = 1e15; // 0.001 ERC20 token
    /// @notice The total supply of tokens
    uint256 public constant TOTAL_SUPPLY_OF_TOKENS = 1e27;
    /// @notice The bera amount threshold to lock the bonding curve
    uint256 public constant BERA_MARKET_CAP_LIQ = 12e18;
    /// @notice Market cap threshold to lock the bonding curve
    uint256 public constant MARKET_CAP = 69e21;
    /// @notice Final balance threshold of the bonding curve
    uint256 public constant CURVE_BALANCE_THRESHOLD = 2e26;

    /// @notice The address that receives the protocol fee
    address payable public immutable feeRecipient;
    /// @notice The factory contract that can register tokens
    address public immutable factory;
    /// @notice The referral manager contract
    IReferralManager public immutable referralManager;
    /// @notice The event tracker contract
    IBuzzEventTracker public immutable eventTracker;
    /// @notice The price decoder contract
    IBexPriceDecoder public immutable priceDecoder;
    /// @notice The liquidity manager contract
    IBexLiquidityManager public immutable liquidityManager;

    /**
     * @notice Data about a token in the bonding curve
     * @param tokenBalance The token balance
     * @param beraBalance The Bera balance
     * @param lastPrice The last price of the token
     * @param beraThreshold The amount of bera on the curve to lock it
     * @param bexListed Whether the token is listed in Bex
     */
    struct TokenInfo {
        uint256 tokenBalance;
        uint256 beraBalance; // aka reserve balance
        uint256 lastPrice;
        uint256 beraThreshold;
        bool bexListed;
    }

    /// @notice Map token address to token info
    mapping(address => TokenInfo) public tokenInfo;

    /**
     * @notice Constructor for a new BuzzVault contract
     * @param _feeRecipient The address that receives the protocol fee
     * @param _factory The factory contract that can register tokens
     * @param _referralManager The referral manager contract
     * @param _eventTracker The event tracker contract
     * @param _priceDecoder The price decoder contract
     * @param _liquidityManager The liquidity manager contract
     */
    constructor(
        address payable _feeRecipient,
        address _factory,
        address _referralManager,
        address _eventTracker,
        address _priceDecoder,
        address _liquidityManager
    ) {
        feeRecipient = _feeRecipient;
        factory = _factory;
        referralManager = IReferralManager(_referralManager);
        eventTracker = IBuzzEventTracker(_eventTracker);
        priceDecoder = IBexPriceDecoder(_priceDecoder);
        liquidityManager = IBexLiquidityManager(_liquidityManager);
    }

    /**
     * @notice Buy tokens from the vault with Bera
     * @param token The token address
     * @param minTokens The minimum amount of tokens to buy, will revert if slippage exceeds this value
     * @param affiliate The affiliate address, zero address if none
     */
    function buy(address token, uint256 minTokens, address affiliate) external payable nonReentrant {
        if (msg.value == 0) revert BuzzVault_QuoteAmountZero();
        
        if (minTokens < MIN_TOKEN_AMOUNT) revert BuzzVault_InvalidMinTokenAmount();

        TokenInfo storage info = tokenInfo[token];
        if (info.tokenBalance == 0 && info.beraBalance == 0) revert BuzzVault_UnknownToken();

        uint256 contractBalance = IERC20(token).balanceOf(address(this));
        if (contractBalance < minTokens) revert BuzzVault_InvalidReserves();

        if (affiliate != address(0)) _setReferral(affiliate, msg.sender);

        uint256 amountBought = _buy(token, minTokens, affiliate, info);
        eventTracker.emitTrade(msg.sender, token, amountBought, msg.value, true);

        // BOILERPLATE CODE -> NEEDS CHANGES!!!!! -> placeholder for final logic -> needs virtual mcap burn + curve buffer + virtual mcap K
        if (getMarketCapFor(token) > MARKET_CAP) {
            info.bexListed = true;

            // collect fee
            // TODO: Check if we need to burn the same DEX_MIGRATION_FEE_BPS amount of tokens to keep the curve balanced
            uint256 dexFee = (info.beraBalance * DEX_MIGRATION_FEE_BPS) / 10000;
            _transferFee(feeRecipient, dexFee);

            IERC20(token).safeApprove(address(liquidityManager), info.tokenBalance);
            liquidityManager.createPoolAndAdd{value: info.beraBalance - dexFee}(token, info.tokenBalance, info.lastPrice);
        }
    }

    /**
     * @notice Sell tokens to the vault for Bera
     * @param token The token address
     * @param tokenAmount The amount of tokens to sell
     * @param minBera The minimum amount of Bera to receive, will revert if slippage exceeds this value
     * @param affiliate The affiliate address, zero address if none
     */
    function sell(address token, uint256 tokenAmount, uint256 minBera, address affiliate) external nonReentrant {
        if (tokenAmount == 0) revert BuzzVault_QuoteAmountZero();

        if (tokenAmount < MIN_TOKEN_AMOUNT) revert BuzzVault_InvalidMinTokenAmount();

        TokenInfo storage info = tokenInfo[token];
        if (info.tokenBalance == 0 && info.beraBalance == 0) revert BuzzVault_UnknownToken();

        if (IERC20(token).balanceOf(msg.sender) < tokenAmount) revert BuzzVault_InvalidUserBalance();

        if (affiliate != address(0)) _setReferral(affiliate, msg.sender);

        uint256 amountSold = _sell(token, tokenAmount, minBera, affiliate, info);
        eventTracker.emitTrade(msg.sender, token, tokenAmount, amountSold, false);
    }

    /**
     * @notice Register a token in the vault
     * @dev Only the factory can register tokens
     * @param token The token address
     * @param tokenBalance The token balance
     */
    function registerToken(address token, uint256 tokenBalance) external {
        if (msg.sender != factory) revert BuzzVault_Unauthorized();
        if (tokenInfo[token].tokenBalance > 0 && tokenInfo[token].beraBalance > 0) revert BuzzVault_TokenExists();

        uint256 beraAmount = _getBeraAmountForMarketCap();

        // Assumption: Token has fixed supply upon deployment
        tokenInfo[token] = TokenInfo(tokenBalance, 0, IERC20(token).totalSupply(), beraAmount, false);

        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenBalance);
    }

    /**
     * @notice Returns the market cap of a token denominated in USD (from a USD-pegged stablecoin)
     * @param token The token address
     * @return marketCap The market cap of the token
     */
    function getMarketCapFor(address token) public view returns (uint256 marketCap) {
        TokenInfo storage info = tokenInfo[token];

        uint256 tokenBalance = info.tokenBalance;

        // Ensure token is valid
        if (tokenBalance == 0 && info.beraBalance == 0) {
            revert BuzzVault_UnknownToken();
        }

        // Get the Bera/USD price (assumed 18 decimals)
        uint256 beraUsdPrice = priceDecoder.getPrice();

        uint256 circulatingSupply = TOTAL_SUPPLY_OF_TOKENS - tokenBalance;
        marketCap = (info.lastPrice * circulatingSupply * beraUsdPrice) / 1e36;
    }

    function quote(address token, uint256 amount, bool isBuyOrder) external view virtual returns (uint256 amountOut, uint256 pricePerToken);

    function _buy(address token, uint256 minTokens, address affiliate, TokenInfo storage info) internal virtual returns (uint256 tokenAmount);

    function _sell(
        address token,
        uint256 tokenAmount,
        uint256 minBera,
        address affiliate,
        TokenInfo storage info
    ) internal virtual returns (uint256 beraAmount);

    /**
     * @notice Transfers bera to a recipient, checking if the transfer was successful
     * @param recipient The recipient address
     * @param amount The amount to transfer
     */
    function _transferFee(address payable recipient, uint256 amount) internal {
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) revert BuzzVault_FeeTransferFailed();
    }

    /**
     * @notice Regisers the referral for a user in ReferralManager
     * @param referrer The referrer address
     * @param user The user address
     */
    function _setReferral(address referrer, address user) internal {
        referralManager.setReferral(referrer, user);
    }

    /**
     * @notice Forwards the referral fee to ReferralManager
     * @param user The user address making the trade
     * @param amount The amount to forward
     */
    function _forwardReferralFee(address user, uint256 amount) internal {
        referralManager.receiveReferral{value: amount}(user);
    }

    /**
     * @notice Returns the basis points from ReferralManager to deduct for referrals
     * @param user The user address
     * @return bps The basis points to deduct
     */
    function _getBpsToDeductForReferrals(address user) internal view returns (uint256 bps) {
        bps = referralManager.getReferralBpsFor(user);
    }

    /**
     * @notice Returns the amount of BERA to register in TokenInfo for a bonding curve lock given the USD market cap liquidity requirements
     * @return beraAmount The amount of BERA for market cap
     */
    function _getBeraAmountForMarketCap() internal view returns (uint256 beraAmount) {
        // Get the Bera/USD price (assumed 18 decimals)
        uint256 beraUsdPrice = priceDecoder.getPrice();

        // Assuming 18 decimal precision
        beraAmount = (BERA_MARKET_CAP_LIQ * 1e18) / beraUsdPrice;
    }
}
