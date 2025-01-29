// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWBera} from "./interfaces/IWBera.sol";
import {IBexLiquidityManager} from "./interfaces/IBexLiquidityManager.sol";
import {IReferralManager} from "./interfaces/IReferralManager.sol";
import {IBuzzVault} from "./interfaces/IBuzzVault.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";

/**
 * @title BuzzVault contract
 * @notice An abstract contract holding logic for bonding curve operations
 * @author nexusflip, 0xMitzie
 */
abstract contract BuzzVault is Ownable, Pausable, IBuzzVault {
    using SafeERC20 for IERC20;

    /// @notice Event emitted when a trade occurs
    event Trade(
        address indexed user,
        address indexed token,
        address indexed baseToken,
        uint256 tokenAmount,
        uint256 baseAmount,
        uint256 tokenBalance,
        uint256 baseBalance,
        bool isBuyOrder
    );
    /// @notice Event emitted when a token is registered
    event TokenRegistered(
        address indexed token,
        address indexed baseToken,
        uint256 tokenBalance,
        uint256 initialReserves,
        uint256 finalReserves
    );

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
    /// @notice Error code emitted when native trades with ETH is not supported
    error BuzzVault_NativeTradeUnsupported();
    /// @notice Error code emitted when WBera transfer fails (depositing or withdrawing)
    error BuzzVault_WBeraConversionFailed();
    /// @notice Error code emitted when the recipient is the zero address
    error BuzzVault_AddressZeroRecipient();
    /// @notice Error code emitted when the token is the zero address
    error BuzzVault_AddressZeroToken();

    /**
     * @notice Data about a token in the bonding curve
     * @param baseToken The base token address
     * @param bexListed Whether the token is listed in Bex
     * @param tokenBalance The token balance
     * @param baseBalance The base amount balance
     * @param initialBase The initial base amount
     * @param baseThreshold The amount of bera on the curve to lock it
     * @param quoteThreshold The amount of tokens on the curve to lock it
     * @param k The k value of the token
     */
    struct TokenInfo {
        address baseToken;
        bool bexListed;
        uint256 tokenBalance;
        uint256 baseBalance; // aka reserve balance
        uint256 initialBase;
        uint256 baseThreshold;
        uint256 quoteThreshold;
        uint256 k;
    }

    /// @notice The fee manager contract collecting protocol fees
    IFeeManager public immutable FEE_MANAGER;
    /// @notice The referral manager contract
    IReferralManager public immutable REFERRAL_MANAGER;
    /// @notice The liquidity manager contract
    IBexLiquidityManager public immutable LIQUIDITY_MANAGER;
    /// @notice The WBERA contract
    IWBera public immutable WBERA;

    /// @notice The factory contract that can register tokens
    address public immutable FACTORY;

    /// @notice Map token address to token info
    mapping(address => TokenInfo) public tokenInfo;

    /**
     * @notice Constructor for a new BuzzVault contract
     * @param _feeManager The address of the fee manager contract collecting fees
     * @param _factory The factory contract that can register tokens
     * @param _referralManager The referral manager contract
     * @param _liquidityManager The liquidity manager contract
     * @param _wbera The WBERA contract
     */
    constructor(
        address _feeManager,
        address _factory,
        address _referralManager,
        address _liquidityManager,
        address _wbera
    ) {
        FACTORY = _factory;
        FEE_MANAGER = IFeeManager(_feeManager);
        REFERRAL_MANAGER = IReferralManager(_referralManager);
        LIQUIDITY_MANAGER = IBexLiquidityManager(_liquidityManager);
        WBERA = IWBera(_wbera);
    }

    // Fallback function
    receive() external payable {}

    /**
     * @notice Buy tokens from the vault with the native currency. The base token of the token must be WBera
     * @param token The token address
     * @param minTokensOut The minimum amount of tokens to buy, will revert if slippage exceeds this value
     * @param affiliate The affiliate address, zero address if none
     * @param recipient The recipient address
     */
    function buyNative(
        address token,
        uint256 minTokensOut,
        address affiliate,
        address recipient
    ) external payable override whenNotPaused {
        if (msg.value == 0) revert BuzzVault_QuoteAmountZero();
        if (recipient == address(0)) revert BuzzVault_AddressZeroRecipient();
        if (token == address(0)) revert BuzzVault_AddressZeroToken();

        TokenInfo storage info = tokenInfo[token];
        if (info.bexListed) revert BuzzVault_BexListed();
        if (info.tokenBalance == 0 && info.baseBalance == 0)
            revert BuzzVault_UnknownToken();

        uint256 contractBalance = IERC20(token).balanceOf(address(this));
        if (contractBalance < minTokensOut) revert BuzzVault_InvalidReserves();

        uint256 baseAmount;
        if (tokenInfo[token].baseToken == address(WBERA)) {
            uint256 balancePrior = WBERA.balanceOf(address(this));
            WBERA.deposit{value: msg.value}();

            baseAmount = WBERA.balanceOf(address(this)) - balancePrior;
            if (baseAmount != msg.value)
                revert BuzzVault_WBeraConversionFailed();
        } else {
            revert BuzzVault_NativeTradeUnsupported();
        }

        _buyTokens(token, baseAmount, minTokensOut, affiliate, recipient, info);
    }

    /**
     * @notice Buy tokens from the vault using the base token (ERC20)
     * @param token The token address
     * @param baseAmount The amount of base tokens to buy with
     * @param minTokensOut The minimum amount of tokens to buy, will revert if slippage exceeds this value
     * @param affiliate The affiliate address, zero address if none
     * @param recipient The recipient address
     */
    function buy(
        address token,
        uint256 baseAmount,
        uint256 minTokensOut,
        address affiliate,
        address recipient
    ) external override whenNotPaused {
        if (baseAmount == 0) revert BuzzVault_QuoteAmountZero();
        if (recipient == address(0)) revert BuzzVault_AddressZeroRecipient();
        if (token == address(0)) revert BuzzVault_AddressZeroToken();

        TokenInfo storage info = tokenInfo[token];
        if (info.bexListed) revert BuzzVault_BexListed();
        if (info.tokenBalance == 0 && info.baseBalance == 0)
            revert BuzzVault_UnknownToken();

        uint256 contractBalance = IERC20(token).balanceOf(address(this));
        if (contractBalance < minTokensOut) revert BuzzVault_InvalidReserves();

        IERC20(tokenInfo[token].baseToken).safeTransferFrom(
            msg.sender,
            address(this),
            baseAmount
        );

        _buyTokens(token, baseAmount, minTokensOut, affiliate, recipient, info);
    }

    /**
     * @notice Sell tokens to the vault for base tokens
     * @param token The (quote) token address
     * @param tokenAmount The amount of (quote) tokens to sell
     * @param minAmountOut The minimum amount of base tokens to receive, will revert if slippage exceeds this value
     * @param affiliate The affiliate address, zero address if none
     * @param recipient The recipient address
     * @param unwrap Whether to unwrap the WBERA tokens to BERA
     */
    function sell(
        address token,
        uint256 tokenAmount,
        uint256 minAmountOut,
        address affiliate,
        address recipient,
        bool unwrap
    ) external override whenNotPaused {
        if (tokenAmount == 0) revert BuzzVault_QuoteAmountZero();
        if (recipient == address(0)) revert BuzzVault_AddressZeroRecipient();
        if (token == address(0)) revert BuzzVault_AddressZeroToken();

        TokenInfo storage info = tokenInfo[token];
        if (info.bexListed) revert BuzzVault_BexListed();
        if (info.tokenBalance == 0 && info.baseBalance == 0)
            revert BuzzVault_UnknownToken();

        if (IERC20(token).balanceOf(msg.sender) < tokenAmount)
            revert BuzzVault_InvalidUserBalance();

        if (affiliate != address(0)) _setReferral(affiliate, msg.sender);

        uint256 amountSold = _sell(
            token,
            tokenAmount,
            minAmountOut,
            recipient,
            info,
            unwrap
        );

        emit Trade(
            recipient,
            token,
            info.baseToken,
            tokenAmount,
            amountSold,
            info.tokenBalance,
            info.baseBalance,
            false
        );
    }

    /**
     * @notice Register a token in the vault
     * @dev Only the factory can register tokens
     * @param token The token address
     * @param baseToken The base token address
     * @param initialTokenBalance The initial quote token balance
     * @param initialReserves The initial virtual base token reserves
     * @param finalReserves The target virtual base token reserves
     */
    function registerToken(
        address token,
        address baseToken,
        uint256 initialTokenBalance,
        uint256 initialReserves,
        uint256 finalReserves
    ) external override {
        if (msg.sender != FACTORY) revert BuzzVault_Unauthorized();
        if (
            tokenInfo[token].tokenBalance > 0 ||
            tokenInfo[token].baseBalance > 0
        ) revert BuzzVault_TokenExists();

        uint256 k = initialReserves * initialTokenBalance;

        tokenInfo[token] = TokenInfo(
            baseToken,
            false,
            initialTokenBalance,
            initialReserves,
            initialReserves,
            finalReserves,
            k / finalReserves,
            k
        );

        IERC20(token).safeTransferFrom(
            msg.sender,
            address(this),
            initialTokenBalance
        );

        emit TokenRegistered(
            token,
            baseToken,
            initialTokenBalance,
            initialReserves,
            finalReserves
        );
    }

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

    /**
     * @notice Quote the amount of tokenIn needed to buy a certain amount of tokenOut
     * @param token The token address
     * @param amount The amount of tokens to buy
     * @param isBuyOrder Whether the quote is for a buy or sell order
     * @return amountOut The amount of base tokens needed
     */
    function quote(
        address token,
        uint256 amount,
        bool isBuyOrder
    ) external view virtual override returns (uint256 amountOut);

    /**
     * @notice Internal function to handle buy accounting
     * @param token The token address
     * @param baseAmount The amount of base tokens to buy with
     * @param minTokensOut The minimum amount of tokens to buy, will revert if slippage exceeds this value
     * @param recipient The recipient address
     * @return tokenAmount The amount of tokens bought
     * @return needsMigration Whether the curve needs to be locked and migrated
     */
    function _buy(
        address token,
        uint256 baseAmount,
        uint256 minTokensOut,
        address recipient,
        TokenInfo storage info
    ) internal virtual returns (uint256 tokenAmount, bool needsMigration);

    /**
     * @notice Internal function to handle sell accounting
     * @param token The token address
     * @param tokenAmount The amount of tokens to sell
     * @param minAmountOut The minimum amount of base tokens to receive, will revert if slippage exceeds this value
     * @param recipient The recipient address
     * @param info The token info struct
     * @param unwrap Whether to unwrap the WBERA tokens to BERA
     * @return netBaseAmount The amount of base tokens received
     */
    function _sell(
        address token,
        uint256 tokenAmount,
        uint256 minAmountOut,
        address recipient,
        TokenInfo storage info,
        bool unwrap
    ) internal virtual returns (uint256 netBaseAmount);

    /**
     * @notice Transfers bera to a recipient, checking if the transfer was successful
     * @param recipient The recipient address
     * @param amount The amount to transfer
     */
    function _transferEther(
        address payable recipient,
        uint256 amount
    ) internal {
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) revert BuzzVault_FeeTransferFailed();
    }

    /**
     * @notice Locks the bonding curve and deposits the tokens in the liquidity manager
     * @param token The token address
     * @param info The token info struct
     */
    function _lockCurveAndDeposit(
        address token,
        TokenInfo storage info
    ) internal {
        uint256 tokenBalance = info.tokenBalance;
        uint256 baseBalance = info.baseBalance - info.initialBase;
        address baseToken = info.baseToken;

        info.bexListed = true;
        info.baseBalance = 0;
        info.tokenBalance = 0;
        info.initialBase = 0;
        info.baseThreshold = 0;
        info.quoteThreshold = 0;
        info.k = 0;

        // collect fee
        uint256 dexFee = FEE_MANAGER.quoteMigrationFee(baseBalance);
        IERC20(baseToken).forceApprove(address(FEE_MANAGER), dexFee);
        FEE_MANAGER.collectMigrationFee(baseToken, baseBalance);
        uint256 netBaseAmount = baseBalance - dexFee;

        IERC20(token).forceApprove(address(LIQUIDITY_MANAGER), tokenBalance);
        IERC20(baseToken).forceApprove(
            address(LIQUIDITY_MANAGER),
            netBaseAmount
        );

        LIQUIDITY_MANAGER.createPoolAndAdd(
            token,
            baseToken,
            netBaseAmount,
            tokenBalance
        );

        // burn any rounding excess
        if (IERC20(token).balanceOf(address(this)) > 0) {
            IERC20(token).safeTransfer(
                address(0xdead),
                IERC20(token).balanceOf(address(this))
            );
        }
    }

    /**
     * @notice Internal function containing the peripheral logic to buy tokens from the bonding curve
     * @param token The token address
     * @param baseAmount The amount of base tokens to buy with
     * @param minTokensOut The minimum amount of tokens to buy, will revert if slippage exceeds this value
     * @param affiliate The affiliate address, zero address if none
     * @param recipient The recipient address
     * @param info The token info struct
     */
    function _buyTokens(
        address token,
        uint256 baseAmount,
        uint256 minTokensOut,
        address affiliate,
        address recipient,
        TokenInfo storage info
    ) internal {
        if (affiliate != address(0)) _setReferral(affiliate, msg.sender);

        (uint256 amountBought, bool needsMigration) = _buy(
            token,
            baseAmount,
            minTokensOut,
            recipient,
            info
        );

        emit Trade(
            recipient,
            token,
            info.baseToken,
            amountBought,
            baseAmount,
            info.tokenBalance,
            info.baseBalance,
            true
        );

        if (needsMigration) {
            _lockCurveAndDeposit(token, info);
        }
    }

    /**
     * @notice Registers the referral for a user in REFERRAL_MANAGER
     * @param referrer The referrer address
     * @param user The user address
     */
    function _setReferral(address referrer, address user) internal {
        REFERRAL_MANAGER.setReferral(referrer, user);
    }

    /**
     * @notice Calculates and forwards the referral fee to REFERRAL_MANAGER
     * @param user The user address making the trade
     * @param token The base token address
     * @param amount The base amount to calculate the fee on
     */
    function _collectReferralFee(
        address user,
        address token,
        uint256 amount
    ) internal returns (uint256 referralFee) {
        uint256 bps = REFERRAL_MANAGER.getReferralBpsFor(user);

        if (bps > 0) {
            referralFee = (amount * bps) / 1e4;
            IERC20(token).forceApprove(address(REFERRAL_MANAGER), referralFee);
            REFERRAL_MANAGER.receiveReferral(user, token, referralFee);
        }
    }

    /**
     * @notice Unwraps the WBERA tokens to BERA
     * @param to The recipient address
     * @param amount The amount to unwrap
     */
    function _unwrap(address to, uint256 amount) internal {
        uint256 balancePrior = address(this).balance;
        IERC20(address(WBERA)).forceApprove(address(WBERA), amount);

        WBERA.withdraw(amount);
        uint256 withdrawal = address(this).balance - balancePrior;
        if (withdrawal != amount) revert BuzzVault_WBeraConversionFailed();

        _transferEther(payable(to), amount);
    }
}
