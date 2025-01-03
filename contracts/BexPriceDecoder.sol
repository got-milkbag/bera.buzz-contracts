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
    /// @notice Error emitted when the token does not exist in the list
    error BexPriceDecoder_TokenDoesNotExist();
    /// @notice Error emitted when the length of the tokens and lpTokens arrays do not match
    error BexPriceDecoder_TokensLengthMismatch();
    /// @notice Error emitted when a token has address(0) in their list
    error BexPriceDecoder_TokenAddressZero();

    /// @notice Emitted when the LP token is added
    event LpTokenAdded(
        address indexed lpToken,
        address indexed baseToken, 
        address indexed quoteToken, 
        uint256 poolIdx
    );
    /// @notice Emitted when the LP token is removed
    event LpTokenRemoved(
        address indexed lpToken,
        address indexed baseToken, 
        address indexed quoteToken, 
        uint256 poolIdx
    );

    ICrocQuery public immutable crocQuery;
    struct LPToken {
        address lpToken;
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

    function addLpTokens(address[] memory tokens_, ILPToken[] memory lpTokens_) public onlyOwner {
        if (tokens_.length != lpTokens_.length) revert BexPriceDecoder_TokensLengthMismatch();

        for (uint256 i; i < tokens_.length;) {
            if (address(lpTokens_[i]) == address(0) || tokens_[i] == address(0)) revert BexPriceDecoder_TokenAddressZero();
            if (lpTokens[tokens_[i]].baseToken != address(0)) revert BexPriceDecoder_TokenAlreadyExists();

            lpTokens[tokens_[i]].lpToken = address(lpTokens_[i]);
            lpTokens[tokens_[i]].baseToken = lpTokens_[i].baseToken();
            lpTokens[tokens_[i]].quoteToken = lpTokens_[i].quoteToken();
            lpTokens[tokens_[i]].poolIdx = lpTokens_[i].poolType();

            emit LpTokenAdded(
                address(lpTokens_[i]), 
                lpTokens_[i].baseToken(), 
                lpTokens_[i].quoteToken(),
                lpTokens_[i].poolType()
            );

            unchecked {
                ++i;
            }
        }
    }

    function removeLpTokens(address[] memory tokens_) external onlyOwner {
        for (uint256 i; i < tokens_.length;) {
            if (tokens_[i] == address(0)) revert BexPriceDecoder_TokenAddressZero();

            address baseToken = lpTokens[tokens_[i]].baseToken;
            if (baseToken == address(0)) revert BexPriceDecoder_TokenDoesNotExist();

            address lpToken = lpTokens[tokens_[i]].lpToken;
            address quoteToken = lpTokens[tokens_[i]].quoteToken;
            uint256 poolIdx = lpTokens[tokens_[i]].poolIdx;

            lpTokens[tokens_[i]].lpToken = address(0);
            lpTokens[tokens_[i]].baseToken = address(0);
            lpTokens[tokens_[i]].quoteToken = address(0);
            lpTokens[tokens_[i]].poolIdx = 0;

            emit LpTokenRemoved(
                lpToken, 
                baseToken, 
                quoteToken, 
                poolIdx
            );

            unchecked {
                ++i;
            }
        }
    }

    function getPrice(address token) external view returns (uint256 price) {
        if (token == address(0)) revert BexPriceDecoder_TokenAddressZero();
        if (lpTokens[token].lpToken == address(0)) revert BexPriceDecoder_TokenDoesNotExist();

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
