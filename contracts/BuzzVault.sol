// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IBexPriceDecoder.sol";
import "./interfaces/IBuzzToken.sol";
import "./interfaces/IBexLiquidityManager.sol";
import "./interfaces/IReferralManager.sol";
import "./interfaces/IWBera.sol";
import "./interfaces/IBuzzVault.sol";
import "./interfaces/IFeeManager.sol";

/// @title BuzzVault contract
/// @notice An abstract contract holding logic for bonding curve operations, leaving the implementation of the curve to child contracts
abstract contract BuzzVault is Ownable, Pausable, ReentrancyGuard, IBuzzVault {
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
    /// @notice Error code emitted when native trades with ETH is not supported
    error BuzzVault_NativeTradeUnsupported();
    /// @notice Error code emitted when WBera transfer fails (depositing or withdrawing)
    error BuzzVault_WBeraConversionFailed();

    /// @notice Event emitted when a trade occurs
    event Trade(
        address indexed user,
        address indexed token,
        address indexed baseToken,
        uint256 tokenAmount,
        uint256 baseAmount,
        uint256 tokenBalance,
        uint256 baseBalance,
        uint256 lastPrice,
        uint256 lastBasePrice,
        uint256 currentPrice,
        uint256 currentBasePrice,
        bool isBuyOrder
    );

    event CurveDataSet(address indexed token, uint256 k, uint256 growthRate, uint256 baseThreshold);

    /// @notice The percentage of total minted supply after BEX migration in bps
    uint256 public constant MIGRATION_LIQ_RATIO_BPS = 2000;
    /// @notice The min ERC20 amount for bonding curve swaps
    uint256 public constant MIN_TOKEN_AMOUNT = 1e14; // 0.0001 ERC20 token
    /// @notice The total supply of tokens minted
    uint256 public constant TOTAL_MINTED_SUPPLY = 8e26;
    /// @notice Final balance threshold of the bonding curve
    uint256 public constant CURVE_BALANCE_THRESHOLD = 2e26;

    /// @notice The fee manager contract collecting protocol fees
    IFeeManager public immutable feeManager;
    /// @notice The factory contract that can register tokens
    address public immutable factory;
    /// @notice The referral manager contract
    IReferralManager public immutable referralManager;
    /// @notice The price decoder contract
    IBexPriceDecoder public immutable priceDecoder;
    /// @notice The liquidity manager contract
    IBexLiquidityManager public immutable liquidityManager;
    /// @notice The WBERA contract
    IWBera public immutable wbera;

    /**
     * @notice Data about a token in the bonding curve
     * @param baseToken The base token address
     * @param lpConduit The LP conduit address
     * @param tokenBalance The token balance
     * @param baseBalance The base amount balance
     * @param lastPrice The last price of the token
     * @param lastBasePrice The last price of the base token
     * @param currentPrice The current price of the token
     * @param currentBasePrice The current price of the base token
     * @param baseThreshold The amount of bera on the curve to lock it
     * @param k The k value of the token
     * @param growthRate The growth rate of the token
     * @param bexListed Whether the token is listed in Bex
     */
    struct TokenInfo {
        address baseToken;
        address lpConduit;
        uint256 tokenBalance;
        uint256 baseBalance; // aka reserve balance
        uint256 lastPrice;
        uint256 lastBasePrice;
        uint256 currentPrice;
        uint256 currentBasePrice;
        uint256 baseThreshold;
        uint256 k;
        uint256 growthRate;
        bool bexListed;
    }

    /// @notice Map token address to token info
    mapping(address => TokenInfo) public tokenInfo;

    /**
     * @notice Constructor for a new BuzzVault contract
     * @param _feeManager The address of the fee manager contract collecting fees
     * @param _factory The factory contract that can register tokens
     * @param _referralManager The referral manager contract
     * @param _priceDecoder The price decoder contract
     * @param _liquidityManager The liquidity manager contract
     */
    constructor(address _feeManager, address _factory, address _referralManager, address _priceDecoder, address _liquidityManager, address _wbera) {
        feeManager = IFeeManager(_feeManager);
        factory = _factory;
        referralManager = IReferralManager(_referralManager);
        priceDecoder = IBexPriceDecoder(_priceDecoder);
        liquidityManager = IBexLiquidityManager(_liquidityManager);
        wbera = IWBera(_wbera);
    }

    /**
     * @notice Buy tokens from the vault with the native currency. The base token of the token must be WBera
     * @param token The token address
     * @param minTokensOut The minimum amount of tokens to buy, will revert if slippage exceeds this value
     * @param affiliate The affiliate address, zero address if none
     */
    function buyNative(address token, uint256 minTokensOut, address affiliate) external payable override nonReentrant whenNotPaused {
        if (msg.value == 0) revert BuzzVault_QuoteAmountZero();

        uint256 baseAmount;
        if (tokenInfo[token].baseToken == address(wbera)) {
            uint256 balancePrior = wbera.balanceOf(address(this));
            wbera.deposit{value: msg.value}();
            baseAmount = wbera.balanceOf(address(this)) - balancePrior;
            if (baseAmount != msg.value) revert BuzzVault_WBeraConversionFailed();
        } else {
            revert BuzzVault_NativeTradeUnsupported();
        }

        _buyTokens(token, baseAmount, minTokensOut, affiliate);
    }

    /**
     * @notice Buy tokens from the vault using the base token (ERC20)
     * @param token The token address
     * @param baseAmount The amount of base tokens to buy with
     * @param minTokensOut The minimum amount of tokens to buy, will revert if slippage exceeds this value
     * @param affiliate The affiliate address, zero address if none
     */
    function buy(address token, uint256 baseAmount, uint256 minTokensOut, address affiliate) external override nonReentrant whenNotPaused {
        IERC20(tokenInfo[token].baseToken).safeTransferFrom(msg.sender, address(this), baseAmount);
        _buyTokens(token, baseAmount, minTokensOut, affiliate);
    }

    /**
     * @notice Sell tokens to the vault for base tokens
     * @param token The (quote) token address
     * @param tokenAmount The amount of (quote) tokens to sell
     * @param minAmountOut The minimum amount of base tokens to receive, will revert if slippage exceeds this value
     * @param affiliate The affiliate address, zero address if none
     */
    function sell(address token, uint256 tokenAmount, uint256 minAmountOut, address affiliate, bool unwrap) external override nonReentrant whenNotPaused {
        if (tokenAmount == 0) revert BuzzVault_QuoteAmountZero();
        if (tokenAmount < MIN_TOKEN_AMOUNT) revert BuzzVault_InvalidMinTokenAmount();
        
        TokenInfo storage info = tokenInfo[token];
        if (info.bexListed) revert BuzzVault_BexListed();
        if (info.tokenBalance == 0 && info.baseBalance == 0) revert BuzzVault_UnknownToken();
    
        if (IERC20(token).balanceOf(msg.sender) < tokenAmount) revert BuzzVault_InvalidUserBalance();

        if (affiliate != address(0)) _setReferral(affiliate, msg.sender);

        uint256 amountSold = _sell(token, tokenAmount, minAmountOut, info, unwrap);
        emit Trade(
            msg.sender,
            token,
            info.baseToken,
            tokenAmount,
            amountSold,
            info.tokenBalance,
            info.baseBalance,
            info.lastPrice,
            info.lastBasePrice,
            info.currentPrice,
            info.currentBasePrice,
            false
        );
    }

    /**
     * @notice Register a token in the vault
     * @dev Only the factory can register tokens
     * @param token The token address
     * @param baseToken The base token address
     * @param tokenBalance The token balance
     * @param marketCap The market cap of the token
     * @param k The initial k of the token
     * @param growthRate The growth rate of the token
     */
    function registerToken(
        address token,
        address baseToken,
        uint256 tokenBalance,
        uint256 marketCap,
        uint256 k,
        uint256 growthRate
    ) external override {
        if (msg.sender != factory) revert BuzzVault_Unauthorized();
        if (tokenInfo[token].tokenBalance > 0 && tokenInfo[token].baseBalance > 0) revert BuzzVault_TokenExists();

        uint256 reserveBera = _getBaseAmountForMarketCap(baseToken, marketCap);

        // Assumption: Token has fixed supply upon deployment
        tokenInfo[token] = TokenInfo(baseToken, address(0), tokenBalance, 0, 0, 0, 0, 0, reserveBera, k, growthRate, false);

        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenBalance);
        emit CurveDataSet(token, k, growthRate, reserveBera);
    }

    function quote(
        address token,
        uint256 amount,
        bool isBuyOrder
    ) external view virtual override returns (uint256 amountOut, uint256 pricePerToken, uint256 pricePerBase);

    function _buy(address token, uint256 baseAmount, uint256 minTokensOut, TokenInfo storage info) internal virtual returns (uint256 tokenAmount);

    function _sell(
        address token,
        uint256 tokenAmount,
        uint256 minAmountOut,
        TokenInfo storage info,
        bool unwrap
    ) internal virtual returns (uint256 netBaseAmount);

    /**
     * @notice Transfers bera to a recipient, checking if the transfer was successful
     * @param recipient The recipient address
     * @param amount The amount to transfer
     */
    function _transferEther(address payable recipient, uint256 amount) internal {
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) revert BuzzVault_FeeTransferFailed();
    }

    /**
     * @notice Locks the bonding curve and deposits the tokens in the liquidity manager
     * @param token The token address
     * @param info The token info struct
     */
    function _lockCurveAndDeposit(address token, TokenInfo storage info) internal {
        uint256 baseBalance = info.baseBalance;

        info.baseBalance = 0;
        info.tokenBalance = 0;
        info.lastPrice = 0;
        info.lastBasePrice = 0;
        info.currentPrice = 0;
        info.currentBasePrice = 0;
        info.baseThreshold = 0;
        info.k = 0;
        info.growthRate = 0;
        info.bexListed = true;

        // collect fee
        uint256 dexFee = feeManager.quoteMigrationFee(baseBalance);
        IERC20(info.baseToken).safeApprove(address(feeManager), dexFee);
        feeManager.collectMigrationFee(info.baseToken, baseBalance);
        uint256 netBaseAmount = baseBalance - dexFee;

        IBuzzToken(token).mint(address(this), CURVE_BALANCE_THRESHOLD);

        IERC20(token).safeApprove(address(liquidityManager), CURVE_BALANCE_THRESHOLD);
        IERC20(info.baseToken).safeApprove(address(liquidityManager), netBaseAmount);

        address lpConduit = liquidityManager.createPoolAndAdd(token, info.baseToken, netBaseAmount, CURVE_BALANCE_THRESHOLD);

        info.lpConduit = lpConduit;
 
        // burn any rounding excess
        if (IERC20(token).balanceOf(address(this)) > 0) {
            IERC20(token).safeTransfer(address(0xdead), IERC20(token).balanceOf(address(this)));
        }
    }

    /**
     * @notice Internal function containing the peripheral logic to buy tokens from the bonding curve using an erc20 base token
     * @param token The token address
     * @param baseAmount The amount of base tokens to buy with
     * @param minTokensOut The minimum amount of tokens to buy, will revert if slippage exceeds this value
     * @param affiliate The affiliate address, zero address if none
     */
    function _buyTokens(address token, uint256 baseAmount, uint256 minTokensOut, address affiliate) internal {
        if (minTokensOut < MIN_TOKEN_AMOUNT) revert BuzzVault_InvalidMinTokenAmount();

        TokenInfo storage info = tokenInfo[token];
        if (info.bexListed) revert BuzzVault_BexListed();
        if (info.tokenBalance == 0 && info.baseBalance == 0) revert BuzzVault_UnknownToken();

        uint256 contractBalance = IERC20(token).balanceOf(address(this));
        if (contractBalance < minTokensOut) revert BuzzVault_InvalidReserves();

        if (affiliate != address(0)) _setReferral(affiliate, msg.sender);

        uint256 amountBought = _buy(token, baseAmount, minTokensOut, info);
        emit Trade(
            msg.sender,
            token,
            info.baseToken,
            amountBought,
            baseAmount,
            info.tokenBalance,
            info.baseBalance,
            info.lastPrice,
            info.lastBasePrice,
            info.currentPrice,
            info.currentBasePrice,
            true
        );

        if (info.tokenBalance == 0) {
            _lockCurveAndDeposit(token, info);
        }
    }

    /**
     * @notice Registers the referral for a user in ReferralManager
     * @param referrer The referrer address
     * @param user The user address
     */
    function _setReferral(address referrer, address user) internal {
        referralManager.setReferral(referrer, user);
    }

    /**
     * @notice Calculates and forwards the referral fee to ReferralManager
     * @param user The user address making the trade
     * @param token The base token address
     * @param amount The base amount to calculate the fee on
     */
    function _collectReferralFee(address user, address token, uint256 amount) internal returns (uint256 referralFee) {
        uint256 bps = referralManager.getReferralBpsFor(user);

        if (bps > 0) {
            referralFee = (amount * bps) / 1e4;
            IERC20(token).safeApprove(address(referralManager), referralFee);
            referralManager.receiveReferral(user, token, referralFee);
        }
    }

    /**
     * @notice Returns the amount of baseToken to register in TokenInfo for a bonding curve lock given the USD market cap liquidity requirements
     * @param baseToken The base token address
     * @param marketCap The market cap of the token
     * @return baseAmount The amount of baseToken for market cap
     */
    function _getBaseAmountForMarketCap(address baseToken, uint256 marketCap) internal view returns (uint256 baseAmount) {
        uint256 baseUsdPrice = priceDecoder.getPrice(baseToken);

        // divide by 5 to represent equivalent amount with 200MM tokens instead of 1B
        uint256 baseAmountToBps = (marketCap * MIGRATION_LIQ_RATIO_BPS * 1e18) / 10000;
        uint256 baseAmountNoFee = baseAmountToBps / baseUsdPrice;

        baseAmount = baseAmountNoFee + feeManager.quoteMigrationFee(baseAmountNoFee);
    }

    //TODO: check if security issue when unwrap true and token is not WBera
    function _unwrap(address to, uint256 amount) internal {
        uint256 balancePrior = address(this).balance;
        IERC20(address(wbera)).safeApprove(address(wbera), amount);

        wbera.withdraw(amount);
        uint256 withdrawal = address(this).balance - balancePrior;
        if (withdrawal != amount) revert BuzzVault_WBeraConversionFailed();

        _transferEther(payable(to), amount);
    }

    function getBaseUsdPrice(address token) external view returns (uint256 beraPrice) {
        beraPrice = priceDecoder.getPrice(token);
    }

    // Fallback function
    receive() external payable {}

    /**
     * @notice Pauses the contract
     * @dev Only the owner can call this function.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     * @dev Only the owner can call this function.
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
