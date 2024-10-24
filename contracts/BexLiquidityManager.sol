// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IBexLiquidityManager.sol";
import "./interfaces/IWBera.sol";
import "./interfaces/bex/ICrocSwapDex.sol";
import "./libraries/SqrtMath.sol";

contract BexLiquidityManager is IBexLiquidityManager {
    using SafeERC20 for IERC20;

    /// @notice Error code emitted when deposit to the WBera contract fails
    error WrappedDepositFailed();

    /// @notice The pool index to use when creating a pool (1% fee)
    uint256 private constant _poolIdx = 36002;
    /// @notice The address of the wrapped Bera token
    IWBera public constant WBERA = IWBera(0x7507c1dc16935B82698e4C63f2746A2fCf994dF8);
    /// @notice The address of the CrocSwap DEX
    ICrocSwapDex public crocSwapDex;

    /**
     * @notice Constructor a new BexLiquidityManager
     * @param _crocSwapDex The address of the CrocSwap DEX
     */
    constructor(address _crocSwapDex) {
        crocSwapDex = ICrocSwapDex(_crocSwapDex);
    }

    /**
     * @notice Create a new pool with WBera and a specified token in Bex and add liquidity to it. Bera needs to be passed as msg.value
     * @dev The caller must approve the contract to transfer the token.
     * @param token The address of the token to add
     * @param amount The amount of tokens to add
     * @param initPrice The initial price of the pool
     */
    function createPoolAndAdd(address token, uint256 amount, uint256 initPrice) external payable {
        // Wrap Bera
        uint256 beraAmount = msg.value;
        WBERA.deposit{value: beraAmount}();

        // Check for wrapped deposit success
        if (IERC20(address(WBERA)).balanceOf(address(this)) == 0) revert WrappedDepositFailed();

        // Transfer and approve tokens
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).safeApprove(address(crocSwapDex), amount);
        IERC20(address(WBERA)).safeApprove(address(crocSwapDex), beraAmount);

        address base = address(WBERA);
        address quote = token;
        uint8 liqCode = 31; // Fixed liquidity based on base tokens
        if (quote < base) {
            base = token;
            quote = address(WBERA);
            liqCode = 32; // Fixed liquidity based on quote tokens
        }

        // WIP - Init price is based on amount of quote tokens per base token.
        uint128 _initPrice = SqrtMath.encodePriceSqrt(initPrice);
        uint128 liquidity = uint128(beraAmount);

        // Create pool
        // initPool subcode, base, quote, poolIdx, price ins q64.64
        bytes memory cmd1 = abi.encode(71, base, quote, _poolIdx, _initPrice);

        // Add liquidity
        // liquidity subcode (fixed in base tokens, fill-range liquidity)
        // liq subcode, base, quote, poolIdx, bid tick, ask tick, liquidity, lower limit, upper limit, res flags, lp conduit
        // because Bex burns a small insignificant amount of tokens, we reduce the liquidity by BURN_AMOUNT
        bytes memory cmd2 = abi.encode(liqCode, base, quote, _poolIdx, 0, 0, liquidity - 1 ether, _initPrice, _initPrice, 0, address(0));

        // Encode commands into a multipath call
        bytes memory encodedCmd = abi.encode(2, 3, cmd1, 128, cmd2);

        // Execute multipath call
        crocSwapDex.userCmd(6, encodedCmd);
    }
}
