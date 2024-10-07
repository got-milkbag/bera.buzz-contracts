// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IWBera.sol";
import "./interfaces/bex/ICrocSwapDex.sol";
import "./libraries/Math64x64.sol";

contract BexLiquidityManager {
    using SafeERC20 for IERC20;

    error WrappedDepositFailed();

    IWBera public constant WBERA = IWBera(0x7507c1dc16935B82698e4C63f2746A2fCf994dF8);
    
    uint256 private constant _poolIdx = 36002;

    ICrocSwapDex public crocSwapDex;

    constructor(address _crocSwapDex) {
        crocSwapDex = ICrocSwapDex(_crocSwapDex);
    }

    function createPoolAndAdd(address token, uint256 amount) external payable {
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
        if (quote < base) {
            base = token;
            quote = address(WBERA);
        }

        // Create pool
        // initPool subcode, base, quote, poolIdx, price ins q64.64
        uint128 _initPrice = uint128(1 << 64);
        bytes memory cmd1 = abi.encode(71, base, quote, _poolIdx, 2e23);

        // Add liquidity
        // liquidity subcode (fixed in base tokens, fill-range liquidity)
        // liq subcode, base, quote, poolIdx, bid tick, ask tick, liquidity, lower limit, upper limit, res flags, lp conduit
        bytes memory cmd2 = abi.encode(31, base, quote, _poolIdx, 0, 0, 1e6, 0, type(uint128).max, 0, address(0));

        // Encode commands into a multipath call
        bytes memory encodedCmd = abi.encode(2, 3, cmd1, 128, cmd2);

        // Execute multipath call
        crocSwapDex.userCmd(6, encodedCmd);
    }
}
