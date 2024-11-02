// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IFeeManager.sol";

/**
 * @title FeeManager
 * @notice This contract collects and forwards to the treasury the different types of fees in the protocol
 */
contract FeeManager is Ownable, IFeeManager {
    using SafeERC20 for IERC20;

    /// @notice Error thrown when treasury is the zero address
    error FeeManager_TreasuryZeroAddress();
    /// @notice Error thrown when the amount is above the fee divisor
    error FeeManager_AmountAboveFeeDivisor();
    /// @notice Error thrown when the fee is insufficient
    error FeeManager_InsufficientFee();

    /// @notice Event emitted when an ERC20 fee is received
    event FeeReceived(address indexed token, uint256 amount);
    /// @notice Event emitted when a native currency fee is received
    event NativeFeeReceived(uint256 amount);
    /// @notice Event emitted when the treasury address is set
    event TreasurySet(address indexed treasury);
    /// @notice Event emitted when the trading fee is set
    event TradingFeeSet(uint256 tradingFeeBps);
    /// @notice Event emitted when the listing fee is set
    event ListingFeeSet(uint256 listingFee);
    /// @notice Event emitted when the migration fee is set
    event MigrationFeeSet(uint256 migrationFeeBps);

    /// @notice The divisor used to calculate fees (one percent equals 1000)
    uint256 public constant FEE_DIVISOR = 1e5;
    /// @notice The trading fee in basis points. (one percent equals 1000)
    uint256 public tradingFeeBps;
    /// @notice The AMM migration fee in basis points. (one percent equals 1000)
    uint256 public migrationFeeBps;
    /// @notice The fixed listing fee amount in the native token that needs to be collected
    uint256 public listingFee;
    /// @notice The treasury address where fees are sent
    address public treasury;

    /**
     * @notice Constructor
     * @param _treasury The treasury address where fees are sent
     * @param _tradingFeeBps The trading fee in basis points (one percent equals 1000)
     * @param _listingFee The listing fee amount
     * @param _migrationFeeBps The AMM migration fee in basis points (one percent equals 1000)
     */
    constructor(address _treasury, uint256 _tradingFeeBps, uint256 _listingFee, uint256 _migrationFeeBps) {
        if (_treasury == address(0)) revert FeeManager_TreasuryZeroAddress();
        if ((_tradingFeeBps > FEE_DIVISOR) || (_migrationFeeBps > FEE_DIVISOR)) revert FeeManager_AmountAboveFeeDivisor();
        treasury = _treasury;
        tradingFeeBps = _tradingFeeBps;
        listingFee = _listingFee;
        migrationFeeBps = _migrationFeeBps;

        emit TreasurySet(_treasury);
        emit TradingFeeSet(_tradingFeeBps);
        emit ListingFeeSet(_listingFee);
        emit MigrationFeeSet(_migrationFeeBps);
    }

    /**
     * @notice Collects the trading fee from the sender
     * @dev Approval needs to be given to this contract prior to calling this function
     * @param token The token address
     * @param amount The net fee amount to collect
     */
    function collectTradingFee(address token, uint256 amount) external {
        _collect(token, amount);
    }

    /**
     * @notice Collects the listing fee in native currency from the sender
     */
    function collectListingFee() external payable {
        if (listingFee > 0) {
            if (msg.value != listingFee) revert FeeManager_InsufficientFee();
            (bool success, ) = treasury.call{value: listingFee}("");
            if (!success) revert FeeManager_InsufficientFee();
            emit NativeFeeReceived(listingFee);
        }
    }

    /**
     * @notice Collects the AMM migration fee from the sender
     * @dev Approval needs to be given to this contract prior to calling this function
     * @param token The token address
     */
    function collectMigrationFee(address token, uint256 amount) external {
        uint256 fee = quoteMigrationFee(amount);
        if (fee > 0) _collect(token, fee);
    }

    /**
     * @notice Quotes the dynamic trading fee for a given amount
     * @dev External contracts should quote the fee to give an approval before calling collect
     * @param amount The amount to quote
     * @return fee The fee amount
     */
    function quoteTradingFee(uint256 amount) public view returns (uint256 fee) {
        if (tradingFeeBps == 0) {
            fee = 0;
        }
        fee = (amount * tradingFeeBps) / FEE_DIVISOR;
    }

    /**
     * @notice Quotes the migration fee
     * @dev External contracts should quote the fee to give an approval before calling collect
     * @param amount The amount to quote
     * @return fee The fee amount
     */
    function quoteMigrationFee(uint256 amount) public view returns (uint256 fee) {
        if (migrationFeeBps == 0) {
            fee = 0;
        }
        fee = (amount * migrationFeeBps) / FEE_DIVISOR;
    }

    // Admin functions

    /**
     * @notice Sets the trading fee basis points
     * @dev Only the owner can call this function
     * @param _feeBps The trading fee in basis points (one percent equals 1000)
     */
    function setTradingFeeBps(uint256 _feeBps) external onlyOwner {
        if (_feeBps > FEE_DIVISOR) revert FeeManager_AmountAboveFeeDivisor();
        tradingFeeBps = _feeBps;
        emit TradingFeeSet(_feeBps);
    }

    /**
     * @notice Sets the listing fee amount
     * @dev Only the owner can call this function
     * @param _listingFee The listing fee amount
     */
    function setListingFee(uint256 _listingFee) external onlyOwner {
        listingFee = _listingFee;
        emit ListingFeeSet(_listingFee);
    }

    /**
     * @notice Sets the AMM migration fee amount
     * @dev Only the owner can call this function
     * @param _feeBps The migration fee amount
     */
    function setMigrationFeeBps(uint256 _feeBps) external onlyOwner {
        if (_feeBps > FEE_DIVISOR) revert FeeManager_AmountAboveFeeDivisor();

        migrationFeeBps = _feeBps;
        emit MigrationFeeSet(_feeBps);
    }

    /**
     * @notice Sets the treasury address
     * @dev Only the owner can call this function
     * @param _treasury The treasury address where fees are sent
     */
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert FeeManager_TreasuryZeroAddress();
        treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    // Internal functions

    /**
     * @notice Internal function to collect an ERC20 fee and send it to the treasury
     * @param token The token address
     * @param amount The amount to collect
     */
    function _collect(address token, uint256 amount) internal {
        IERC20(token).safeTransferFrom(_msgSender(), treasury, amount);
        emit FeeReceived(token, amount);
    }

    // Fallback function
    receive() external payable {}
}
