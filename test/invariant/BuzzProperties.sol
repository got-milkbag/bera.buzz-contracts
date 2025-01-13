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
    }

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
    }

    function highlightsQuote(uint256 randDuration) public {
        User user = users[randDuration % users.length];

        uint256 duration = clampBetween(randDuration, 60, HARD_CAP);

        (bool success, ) = user.proxy(
            address(highlightsManager),
            abi.encodeWithSelector(highlightsManager.quote.selector, duration)
        );
        require(success);
    }

    // ---------------------- Invariants -------------------------------
}
