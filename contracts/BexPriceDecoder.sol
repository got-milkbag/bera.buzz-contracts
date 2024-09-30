// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./libraries/FixedPoint64.sol";
import "./interfaces/bex/ILPToken.sol";
import "./interfaces/bex/ICrocQuery.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

contract BexPriceDecoder is Ownable {
    using FixedPoint64 for uint160;

    ICrocQuery public crocQuery;
    ILPToken public lpToken;

    uint256 private poolIdx;
    address private baseToken;
    address private quoteToken;

    constructor(ILPToken _lpToken, ICrocQuery _crocQuery) {
        lpToken = _lpToken;
        crocQuery = _crocQuery;

        poolIdx = lpToken.poolType();
        baseToken = lpToken.baseToken();
        quoteToken = lpToken.quoteToken();
    }

    function setLpToken(ILPToken _lpToken) external onlyOwner {
        lpToken = _lpToken;

        poolIdx = lpToken.poolType();
        baseToken = lpToken.baseToken();
        quoteToken = lpToken.quoteToken();
    }

    function getPrice() external view returns (uint256 price) {
        uint128 sqrtPriceX64 = crocQuery.queryPrice(baseToken, quoteToken, poolIdx);
        price = _getPriceFromSqrtPriceX64(sqrtPriceX64);
    }

    /// @notice Tokens should have 18 decimals
    function _getPriceFromSqrtPriceX64(uint160 sqrtPriceX64) internal pure returns (uint256 price) {
        price = sqrtPriceX64.decodeSqrtPriceX64();
    }
}
