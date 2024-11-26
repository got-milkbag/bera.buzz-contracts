// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IFeeManager {
    function listingFee() external view returns (uint256);

    function collectListingFee() external payable;

    function collectTradingFee(address token, uint256 amount) external;

    function collectMigrationFee(address token, uint256 amount) external;

    function quoteTradingFee(uint256 amount) external view returns (uint256 fee);

    function quoteMigrationFee(uint256 amount) external view returns (uint256 fee);

    function migrationFeeBps() external view returns (uint256);
}
