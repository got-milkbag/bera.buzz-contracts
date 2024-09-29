// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./interfaces/IWBera.sol";
import "./interfaces/bex/ICrocSwapDex.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BexLiquidityManager {
    IWBera public constant WBERA = IWBera(0x7507c1dc16935B82698e4C63f2746A2fCf994dF8);

    ICrocSwapDex public crocSwapDex;

    uint256 private constant _poolIdx = 36001;

    constructor(address _crocSwapDex) {
        crocSwapDex = ICrocSwapDex(_crocSwapDex);
    }

    function createPoolAndAdd(address token, uint256 amount) external payable {
        // Wrap Bera
        uint256 beraAmount = msg.value;
        WBERA.deposit{value: beraAmount}();

        // Transfer and approve tokens
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        IERC20(token).approve(address(crocSwapDex), amount);

        // Create pool
        // initPool subcode, base, quote, poolIdx, price in q64.64
        uint160 _initPrice = uint160(1 << 64);
        bytes memory cmd1 = abi.encode(71, address(WBERA), token, _poolIdx, _initPrice);

        // Add liquidity
        // liquidity subcode (fixed in base tokens, fill-range liquidity)
        // liq subcode, base, quote, poolIdx, bid tick, ask tick, liquidity, lower limit, upper limit, res flags, lp conduit
        bytes memory cmd2 = abi.encode(31, address(WBERA), token, _poolIdx, 0, 0, beraAmount, 0, 2 ** 256 - 1, address(0));

        // Encode commands into a multipath call
        bytes memory encodedCmd = abi.encode(2, 3, cmd1, 128, cmd2);

        // Execute multipath call
        bytes memory result = crocSwapDex.userCmd(6, encodedCmd);
    }
}
