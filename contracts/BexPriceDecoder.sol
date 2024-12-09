// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/FixedPoint64.sol";

import "./interfaces/IBexPriceDecoder.sol";
import "./interfaces/bex/ICrocQuery.sol";
import "./interfaces/bex/ILPToken.sol";

contract BexPriceDecoder is Ownable, IBexPriceDecoder {
    using FixedPoint64 for uint128;

    /// @notice Error emitted when the token already exists in the list
    error BexPriceDecoder_TokenAlreadyExists();
    /// @notice Error emitted when the length of the tokens and lpTokens arrays do not match
    error BexPriceDecoder_TokensLengthMismatch();

    /// @notice Emitted when the LP token is added
    event LpTokenAdded(address indexed baseToken, address indexed quoteToken, uint256 poolIdx);

    ICrocQuery public immutable crocQuery;
    struct LPToken {
        address baseToken;
        address quoteToken;
        uint256 poolIdx;
    }
    mapping(address => LPToken) public lpTokens;

    constructor(
        ICrocQuery _crocQuery, 
        address[] memory _tokens, 
        ILPToken[] memory _lpTokens
    ) {
        addLpTokens(_tokens, _lpTokens);

        crocQuery = _crocQuery;
    }

    function addLpTokens(address[] memory _tokens, ILPToken[] memory _lpTokens) public onlyOwner {
        if(_tokens.length != _lpTokens.length) revert BexPriceDecoder_TokensLengthMismatch();

        for (uint256 i; i < _tokens.length;) {
            if (lpTokens[_tokens[i]].baseToken != address(0)) revert BexPriceDecoder_TokenAlreadyExists();

            address baseToken = _lpTokens[i].baseToken();
            address quoteToken = _lpTokens[i].quoteToken();
            uint256 poolIdx = _lpTokens[i].poolType();

            lpTokens[_tokens[i]].baseToken = baseToken;
            lpTokens[_tokens[i]].quoteToken = quoteToken;
            lpTokens[_tokens[i]].poolIdx = poolIdx;

            emit LpTokenAdded(baseToken, quoteToken, poolIdx);

            unchecked {
                ++i;
            }
        }
    }

    function getPrice(address token) external view returns (uint256 price) {
        uint128 sqrtPriceX64 = crocQuery.queryPrice(
            lpTokens[token].baseToken, 
            lpTokens[token].quoteToken, 
            lpTokens[token].poolIdx
        );

        price = _getPriceFromSqrtPriceX64(sqrtPriceX64);
    }

    /// @notice Tokens should have 18 decimals
    function _getPriceFromSqrtPriceX64(uint128 sqrtPriceX64) internal pure returns (uint256 price) {
        price = sqrtPriceX64.decodeSqrtPriceX64();
    }
}
