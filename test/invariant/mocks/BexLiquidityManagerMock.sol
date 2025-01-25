// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BexLiquidityManagerMock {
    using SafeERC20 for IERC20;

    function createPoolAndAdd(address token, address baseToken, uint256 baseAmount, uint256 amount) external {
        // Transfer and approve tokens
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(baseToken).safeTransferFrom(msg.sender, address(this), baseAmount);
        IERC20(token).safeTransfer(address(0xdead), amount);
        IERC20(baseToken).safeTransfer(address(0xdead), baseAmount);
    }
}
