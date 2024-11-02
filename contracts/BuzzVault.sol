// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
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
abstract contract BuzzVault is ReentrancyGuard, IBuzzVault {
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
    /// @notice Error code emitted when curve softcap has been reached
    //error BuzzVault_SoftcapReached();

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
        uint256 lastBeraPrice,
        bool isBuyOrder
    );

    /// @notice The protocol fee in basis points
    uint256 public constant PROTOCOL_FEE_BPS = 100; // 100 -> 1%
    /// @notice The DEX migration fee in basis points
    uint256 public constant DEX_MIGRATION_FEE_BPS = 420; // 420 -> 4.2%
    /// @notice The min ERC20 amount for bonding curve swaps
    uint256 public constant MIN_TOKEN_AMOUNT = 1e15; // 0.001 ERC20 token
    /// @notice The total supply of tokens
    uint256 public constant TOTAL_SUPPLY_OF_TOKENS = 1e27;
    /// @notice Final balance threshold of the bonding curve
    uint256 public constant CURVE_BALANCE_THRESHOLD = 2e26;
    /// @notice Initial tokens to sell in the curve
    uint256 public constant CURVE_INITIAL_SELL = 8e26;
    /// @notice The bonding curve alpha coefficient
    uint256 public constant CURVE_ALPHA = 202848073251;
    /// @notice The bonding curve beta coefficient
    uint256 public constant CURVE_BETA = 3350000000;
    /// @notice The market cap threshold
    uint256 public constant BERA_MARKET_CAP_LIQ = 69420 ether;
    /// @notice The reserve Bera amount to lock the bonding curve out (calculated at 22/10 02:28 UTC)
    uint256 public constant RESERVE_BERA = 822.6 ether;

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
     * @param tokenBalance The token balance
     * @param baseBalance The base amount balance
     * @param lastPrice The last price of the token
     * @param beraThreshold The amount of bera on the curve to lock it
     * @param bexListed Whether the token is listed in Bex
     */
    struct TokenInfo {
        address baseToken;
        uint256 tokenBalance;
        uint256 baseBalance; // aka reserve balance
        uint256 lastPrice;
        uint256 lastBeraPrice;
        //uint256 beraThreshold;
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
     * @notice Buy tokens from the vault with Bera. The base token of the token must be WBera
     * @param token The token address
     * @param minTokensOut The minimum amount of tokens to buy, will revert if slippage exceeds this value
     * @param affiliate The affiliate address, zero address if none
     */
    function buyNative(address token, uint256 minTokensOut, address affiliate) external payable override nonReentrant {
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
    function buy(address token, uint256 baseAmount, uint256 minTokensOut, address affiliate) external override nonReentrant {
        IERC20(tokenInfo[token].baseToken).safeTransferFrom(msg.sender, address(this), baseAmount);
        _buyTokens(token, baseAmount, minTokensOut, affiliate);
    }

    function _buyTokens(address token, uint256 baseAmount, uint256 minTokensOut, address affiliate) internal {
        if (minTokensOut < MIN_TOKEN_AMOUNT) revert BuzzVault_InvalidMinTokenAmount();

        TokenInfo storage info = tokenInfo[token];
        if (info.tokenBalance == 0 && info.baseBalance == 0) revert BuzzVault_UnknownToken();

        if (info.bexListed) revert BuzzVault_BexListed();

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
            info.lastBeraPrice,
            true
        );

        if (info.baseBalance >= RESERVE_BERA /*info.beraThreshold*/ /*&& info.tokenBalance < CURVE_BALANCE_THRESHOLD*/) {
            _lockCurveAndDeposit(token, info);
        }
    }

    /**
     * @notice Sell tokens to the vault for Bera
     * @param token The token address
     * @param tokenAmount The amount of tokens to sell
     * @param minAmountOut The minimum amount of base token to receive, will revert if slippage exceeds this value
     * @param affiliate The affiliate address, zero address if none
     */
    function sell(address token, uint256 tokenAmount, uint256 minAmountOut, address affiliate, bool unwrap) external override nonReentrant {
        if (tokenAmount == 0) revert BuzzVault_QuoteAmountZero();

        if (tokenAmount < MIN_TOKEN_AMOUNT) revert BuzzVault_InvalidMinTokenAmount();

        TokenInfo storage info = tokenInfo[token];
        if (info.tokenBalance == 0 && info.baseBalance == 0) revert BuzzVault_UnknownToken();

        if (info.bexListed) revert BuzzVault_BexListed();

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
            info.lastBeraPrice,
            false
        );
    }

    /**
     * @notice Register a token in the vault
     * @dev Only the factory can register tokens
     * @param token The token address
     * @param tokenBalance The token balance
     */
    function registerToken(address token, address baseToken, uint256 tokenBalance) external override {
        if (msg.sender != factory) revert BuzzVault_Unauthorized();
        if (tokenInfo[token].tokenBalance > 0 && tokenInfo[token].baseBalance > 0) revert BuzzVault_TokenExists();

        //uint256 reserveBera = _getBeraAmountForMarketCap();

        // Assumption: Token has fixed supply upon deployment
        tokenInfo[token] = TokenInfo(baseToken, tokenBalance, 0, 0, 0, /*reserveBera,*/ false);

        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenBalance);
    }

    function quote(
        address token,
        uint256 amount,
        bool isBuyOrder
    ) external view virtual override returns (uint256 amountOut, uint256 pricePerToken, uint256 pricePerBera);

    function _buy(address token, uint256 baseAmount, uint256 minTokens, TokenInfo storage info) internal virtual returns (uint256 tokenAmount);

    function _sell(
        address token,
        uint256 tokenAmount,
        uint256 minAmountOut,
        TokenInfo storage info,
        bool unwrap
    ) internal virtual returns (uint256 beraAmount);

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
        uint256 lastBeraPrice = info.lastBeraPrice;

        info.baseBalance = 0;
        info.tokenBalance = 0;
        info.lastBeraPrice = 0;
        info.lastPrice = 0;
        info.bexListed = true;

        // collect fee
        uint256 dexFee = feeManager.quoteMigrationFee(baseBalance);
        IERC20(info.baseToken).approve(address(feeManager), dexFee);
        feeManager.collectMigrationFee(info.baseToken, baseBalance);
        uint256 netBeraAmount = baseBalance - dexFee;

        // burn tokens
        //uint256 balancedAmount = (dexFee * lastBeraPrice) / 1e18;
        //IERC20(token).safeTransfer(address(0x1), balancedAmount);
        //uint256 netTokenAmount = tokenBalance - balancedAmount;

        IBuzzToken(token).mint(address(this), CURVE_BALANCE_THRESHOLD);

        IERC20(token).safeApprove(address(liquidityManager), CURVE_BALANCE_THRESHOLD /*- balancedAmount*/);
        liquidityManager.createPoolAndAdd{value: netBeraAmount}(token, CURVE_BALANCE_THRESHOLD, lastBeraPrice);

        // burn any rounding excess
        if (IERC20(token).balanceOf(address(this)) > 0) {
            IERC20(token).safeTransfer(address(0x1), IERC20(token).balanceOf(address(this)));
        }
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
}
