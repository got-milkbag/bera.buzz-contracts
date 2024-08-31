// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BuzzVault is ReentrancyGuard {
    error BuzzVault_InvalidAmount();
    error BuzzVault_InvalidReserves();
    error BuzzVault_SlippageExceeded();

    uint256 public feeBps; // eg 100
    uint256 public reserveTokens;
    uint256 public reserveBera;
    IERC20 public token;

    constructor(address _token) {
        token = IERC20(_token);
    }

    function buy(
        uint256 minTokens,
        address affiliate
    ) public payable nonReentrant {
        if (minTokens == 0) revert BuzzVault_InvalidAmount();
        uint256 berraAmount = msg.value;
        uint256 berraAmountFee = (berraAmount * feeBps) / 10000;

        uint256 tokenAmount = _getAmountFromCurve(
            berraAmount - berraAmountFee,
            reserveBera,
            reserveTokens
        );
        if (tokenAmount < minTokens) revert BuzzVault_SlippageExceeded();
        _updateReservesBuy(berraAmount - berraAmountFee, tokenAmount); // Berra amount should be passed without fee

        // TODO - Implement Affiliate & Owner fee logic, transfer fees

        token.transfer(msg.sender, tokenAmount);
        // TODO - Call Event Tracker
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

    function _updateReservesBuy(
        uint256 berraAmount,
        uint256 tokenAmount
    ) internal {
        reserveBera += berraAmount;
        reserveTokens -= tokenAmount;
    }

    function _updateReservesSell(
        uint256 berraAmount,
        uint256 tokenAmount
    ) internal {
        reserveBera -= berraAmount;
        reserveTokens += tokenAmount;
    }
}
