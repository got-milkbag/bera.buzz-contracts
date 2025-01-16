// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Base} from "./Base.sol";
import {hevm} from "@crytic/properties/contracts/util/Hevm.sol";
import {User} from "./utils/User.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BuzzProperties is Base {
    uint256 internal constant IBGT_AMOUNT = 1_000_000e18;
    uint256 internal constant WBERA_AMOUNT = 1_000_000e18;
    uint256 internal constant NECT_AMOUNT = 100_000_000e18;

    constructor() {
        for (uint256 i; i < NUMBER_OF_USERS; ++i) {
            User user = users[i];

            hevm.deal(address(user), WBERA_AMOUNT);
            hevm.prank(address(user));
            wBERA.deposit{value: WBERA_AMOUNT}();
            iBGT.mint(address(user), IBGT_AMOUNT);
            NECT.mint(address(user), NECT_AMOUNT);

            iBGT.approve(address(buzzTokenFactory), IBGT_AMOUNT);
            wBERA.approve(address(buzzTokenFactory), WBERA_AMOUNT);
            NECT.approve(address(buzzTokenFactory), NECT_AMOUNT);

            iBGT.approve(address(buzzVaultExponential), IBGT_AMOUNT);
            wBERA.approve(address(buzzVaultExponential), WBERA_AMOUNT);
            NECT.approve(address(buzzVaultExponential), NECT_AMOUNT);
        }
    }

    // ---------------------- Handlers -------------------------------

    function buy(
        uint256 randToken,
        uint256 randBaseAmount,
        uint256 randMinTokensOut
    ) public {
        User user = users[randToken % users.length];

        address token = quoteTokens[randToken % quoteTokens.length];
        address baseToken = baseTokens[randToken % baseTokens.length];
        uint256 amount = clampBetween(
            randBaseAmount,
            1,
            IERC20(baseToken).balanceOf(address(user))
        );
        uint256 minAmountOut = clampBetween(randMinTokensOut, 1, amount);
        require(IERC20(baseToken).balanceOf(address(user)) >= amount);

        (bool success, ) = user.proxy(
            address(buzzTokenFactory),
            abi.encodeWithSelector(
                buzzVaultExponential.buy.selector,
                token,
                amount,
                minAmountOut,
                address(0),
                address(user)
            )
        );
        require(success);
    }

    function sell(
        uint256 randToken,
        uint256 randTokenAmount,
        uint256 randMinBaseOut
    ) public {
        User user = users[randToken % users.length];

        address token = quoteTokens[randToken % quoteTokens.length];
        address baseToken = baseTokens[randToken % baseTokens.length];
        uint256 amount = clampBetween(
            randTokenAmount,
            1,
            IERC20(token).balanceOf(address(user))
        );
        uint256 minAmountOut = clampBetween(randMinBaseOut, 1, amount);
        require(
            IERC20(baseToken).balanceOf(address(buzzTokenFactory)) >= amount
        );

        (bool success, ) = user.proxy(
            address(buzzTokenFactory),
            abi.encodeWithSelector(
                buzzVaultExponential.sell.selector,
                token,
                amount,
                minAmountOut,
                address(0),
                address(user),
                false
            )
        );
        require(success);
    }

    /*
    function quote(uint256 randToken, uint256 randAmount) public {
        User user = users[randToken % users.length];
        bool isBuyOrder = randToken % 2 == 0;

        address token = quoteTokens[randToken % quoteTokens.length];
        address baseToken = baseTokens[randToken % baseTokens.length];
        uint256 amount = isBuyOrder
            ? clampBetween(
                randAmount,
                1,
                IERC20(baseToken).balanceOf(address(user))
            )
            : clampBetween(
                randAmount,
                1,
                IERC20(token).balanceOf(address(user))
            );
        require(
            isBuyOrder
                ? IERC20(baseToken).balanceOf(address(user)) >= amount
                : IERC20(baseToken).balanceOf(address(buzzTokenFactory)) >=
                    amount
        );

        (bool success, ) = user.proxy(
            address(buzzTokenFactory),
            abi.encodeWithSelector(
                buzzVaultExponential.quote.selector,
                token,
                amount,
                isBuyOrder
            )
        );
        require(success);
    }*/

    /*
    function claimReferralReward(uint256 randToken) public {
        User user = users[randToken % users.length];

        address token = quoteTokens[randToken % quoteTokens.length];
        address baseToken = baseTokens[randToken % baseTokens.length];
        //TODO: change requirement to only feed tx if referral reward is available
        require(IERC20(baseToken).balanceOf(address(referralManager)) >= 1);

        (bool success, ) = user.proxy(
            address(referralManager),
            abi.encodeWithSelector(
                referralManager.claimReferralReward.selector,
                token
            )
        );
        require(success);
    }

    function highlightToken(uint256 randToken, uint256 randDuration) public {
        User user = users[randToken % users.length];

        address token = quoteTokens[randToken % quoteTokens.length];
        uint256 duration = clampBetween(randDuration, 60, HARD_CAP);
        require(highlightsManager.bookedUntil() <= block.timestamp);
        require(highlightsManager.tokenCoolDownUntil(token) <= block.timestamp);

        (bool success, ) = user.payableProxy{
            value: highlightsManager.quote(duration)
        }(
            address(highlightsManager),
            abi.encodeWithSelector(
                highlightsManager.highlightToken.selector,
                token,
                duration
            )
        );
        require(success);
    }*/

    /*
    function highlightsQuote(uint256 randDuration) public {
        User user = users[randDuration % users.length];

        uint256 duration = clampBetween(randDuration, 60, HARD_CAP);

        (bool success, ) = user.proxy(
            address(highlightsManager),
            abi.encodeWithSelector(highlightsManager.quote.selector, duration)
        );
        require(success);
    }*/

    // ---------------------- Invariants -------------------------------

    /// @custom:invariant The product of tokenBalance and baseBalance must always equal the constant product (K)
    function constantProduct() public view {
        for (uint256 i; i < quoteTokens.length; ++i) {
            address token = quoteTokens[i];
            (
                ,
                ,
                uint256 tokenBalance,
                uint256 baseBalance,
                ,
                ,
                ,
                uint256 k
            ) = buzzVaultExponential.tokenInfo(token);

            assert(tokenBalance * baseBalance == k);
        }
    }

    /// @custom:invariant The baseBalance must never be below initialBase
    function baseBalanceGeInitial() public view {
        for (uint256 i; i < quoteTokens.length; ++i) {
            address token = quoteTokens[i];
            (
                ,
                ,
                ,
                uint256 baseBalance,
                uint256 initialBase,
                ,
                ,

            ) = buzzVaultExponential.tokenInfo(token);

            assert(baseBalance >= initialBase);
        }
    }

    /// @custom:invariant The quote balance must never be below quoteThreshold
    function quoteBalanceGeThreshold() public view {
        for (uint256 i; i < quoteTokens.length; ++i) {
            address token = quoteTokens[i];
            (
                ,
                ,
                uint256 tokenBalance,
                ,
                ,
                ,
                uint256 quoteThreshold,

            ) = buzzVaultExponential.tokenInfo(token);

            assert(tokenBalance >= quoteThreshold);
        }
    }

    /// @custom:invariant The sum of quote tokens in the curves plus tokens held by all users must always be equal to the initial supply
    function quoteTokenSumEqTotalSupply() public view {
        for (uint256 i; i < quoteTokens.length; ++i) {
            uint256 totalSupplyInContract = 0;
            uint256 totalUserBalances = 0;

            address token = quoteTokens[i];
            (, , uint256 tokenBalance, , , , , ) = buzzVaultExponential
                .tokenInfo(token);

            totalSupplyInContract += tokenBalance;

            for (uint256 j; j < users.length; ++j) {
                totalUserBalances += IERC20(token).balanceOf(address(users[i]));
            }

            assert(
                totalUserBalances + totalSupplyInContract ==
                    IERC20(token).totalSupply()
            );
        }
    }

    /// @custom:invariant The quote output must always be less than or equal to the current token balance when buying
    function quoteBuyOutputLeTokenBalance(uint256 randAmount) public view {
        for (uint256 i; i < quoteTokens.length; ++i) {
            address token = quoteTokens[i];
            (, , uint256 tokenBalance, , , , , ) = buzzVaultExponential
                .tokenInfo(token);

            uint256 amountOut = buzzVaultExponential.quote(
                token,
                randAmount,
                true
            );

            assert(amountOut <= tokenBalance);
        }
    }

    /// @custom:invariant The quote output must always be less than or equal to the current token balance when selling
    function quoteSellOutputLeBaseBalance(uint256 randAmount) public view {
        for (uint256 i; i < quoteTokens.length; ++i) {
            address token = quoteTokens[i];
            (, , , uint256 baseBalance, , , , ) = buzzVaultExponential
                .tokenInfo(token);

            uint256 amountOut = buzzVaultExponential.quote(
                token,
                randAmount,
                false
            );

            assert(amountOut <= baseBalance);
        }
    }

    /// @custom:invariant The user must never be able to buy more than initialSupply - finalSupply quote tokens
    function quoteBuyOutputLeInitialMinusFinal(uint256 randAmount) public {
        for (uint256 i; i < quoteTokens.length; ++i) {
            address token = quoteTokens[i];
            (
                ,
                ,
                ,
                ,
                ,
                uint256 baseThreshold,
                uint256 quoteThreshold,

            ) = buzzVaultExponential.tokenInfo(token);
            uint256 amount = clampBetween(
                randAmount,
                baseThreshold,
                type(uint256).max
            );

            uint256 amountOut = buzzVaultExponential.quote(token, amount, true);

            assert(amountOut <= IERC20(token).totalSupply() - quoteThreshold);
        }
    }

    /// @custom:invariant The user must never be able to sell into more than finalReserves - initialReserves base tokens
    function quoteSellOutputLeFinalMinusInitial(uint256 randAmount) public {
        for (uint256 i; i < quoteTokens.length; ++i) {
            address token = quoteTokens[i];
            (
                ,
                ,
                ,
                ,
                uint256 initialBase,
                uint256 baseThreshold,
                uint256 quoteThreshold,

            ) = buzzVaultExponential.tokenInfo(token);
            uint256 amount = clampBetween(
                randAmount,
                IERC20(token).totalSupply() - quoteThreshold,
                type(uint256).max
            );

            uint256 amountOut = buzzVaultExponential.quote(
                token,
                amount,
                false
            );

            assert(amountOut <= baseThreshold - initialBase);
        }
    }
}
