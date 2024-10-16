// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {WETH} from "solady/src/tokens/WETH.sol";

contract WBERA is WETH {
    /// @dev Returns the name of the token.
    function name() public pure override returns (string memory) {
        return "Wrapped Bera";
    }

    /// @dev Returns the symbol of the token.
    function symbol() public pure override returns (string memory) {
        return "WBERA";
    }
}
