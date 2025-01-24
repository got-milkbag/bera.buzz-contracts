// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {BuzzTokenFactory} from "../contracts/BuzzTokenFactory.sol";
import {BuzzVaultExponential} from "../contracts/BuzzVaultExponential.sol";
import {FeeManager} from "../contracts/FeeManager.sol";
import {HighlightsManager} from "../contracts/HighlightsManager.sol";
import {ReferralManager} from "../contracts/ReferralManager.sol";
import {BexLiquidityManager} from "../contracts/BexLiquidityManager.sol";
import {ERC20Mock} from "../test/invariant/mocks/ERC20Mock.sol";
import {WBERA} from "../contracts/mock/WBERA.sol";
import {TokenVesting} from "../contracts/TokenVesting.sol";

contract Helper is Test {
    uint256 internal constant NUMBER_OF_BASE_TOKENS = 3;
    uint256 internal constant TRADING_FEE_BPS = 100;
    uint256 internal constant LISTING_FEE = 2e15;
    uint256 internal constant MIGRATION_FEE_BPS = 420;
    uint256 internal constant DIRECT_REF_FEE_BPS = 1500;
    uint256 internal constant INDIRECT_REF_FEE_BPS = 100;
    uint256 internal constant VALID_UNTIL = 1736450876 + 31536000;
    uint256 internal constant BASE_TOKEN_MIN_RESERVE_AMOUNT = 1e15;
    uint256 internal constant BASE_TOKEN_MIN_RAISE_AMOUNT = 1e18;
    uint256 internal constant HARD_CAP = 3600;
    uint256 internal constant HIGHLIGHTS_BASE_FEE = 5e14;
    uint256 internal constant COOL_DOWN_PERIOD = 86400;
    uint256 internal constant PAYOUT_THRESHOLD_WBERA = 0;
    uint256 internal constant PAYOUT_THRESHOLD_IBGT = 0;
    uint256 internal constant PAYOUT_THRESHOLD_NECT = 0;

    address internal constant CREATE_DEPLOYER =
        0xE088cf94c8C0200022E15e86fc4F9f3A4B2F6e5c;
    address internal constant POOL_FACTORY =
        0x09836Ff4aa44C9b8ddD2f85683aC6846E139fFBf;
    address internal constant BEX_VAULT =
        0x9C8a5c82e797e074Fe3f121B326b140CEC4bcb33;
    address internal constant ADMIN = address(1);
    address internal constant ALICE = address(2);
    address internal constant BOB = address(3);
    address internal constant CHARLIE = address(4);
    address payable internal constant TREASURY = payable(address(0x5));
    address payable internal constant FEE_RECIPIENT = TREASURY;
    string internal constant BERACHAIN_RPC =
        "https://rockbeard-eth-cartio.berachain.com/";

    BuzzTokenFactory internal buzzTokenFactory;
    BuzzVaultExponential internal buzzVaultExponential;
    FeeManager internal feeManager;
    HighlightsManager internal highlightsManager;
    ReferralManager internal referralManager;
    BexLiquidityManager internal bexLiquidityManager;
    TokenVesting internal tokenVesting;

    WBERA internal wBERA;
    ERC20Mock internal iBGT;
    ERC20Mock internal NECT;

    address[] internal baseTokens;
    address[] internal quoteTokens;

    function setUp() public {
        uint256 beraId = vm.createFork(BERACHAIN_RPC);
        vm.selectFork(beraId);
        vm.rollFork(586534);

        vm.startPrank(ADMIN);

        _deployBaseTokens();
        _deployProtocol();
        _initializeProtocol();
        _deployTokens();

        vm.stopPrank();
    }

    function _deployBaseTokens() internal {
        iBGT = new ERC20Mock("iBGT", "iBGT", 18);
        NECT = new ERC20Mock("NECT", "NECT", 18);
        wBERA = new WBERA();
    }

    function _deployProtocol() internal {
        baseTokens = new address[](NUMBER_OF_BASE_TOKENS);
        uint256[] memory baseTokenPayouts = new uint256[](
            NUMBER_OF_BASE_TOKENS
        );

        baseTokens[0] = address(wBERA);
        baseTokens[1] = address(iBGT);
        baseTokens[2] = address(NECT);

        baseTokenPayouts[0] = PAYOUT_THRESHOLD_WBERA;
        baseTokenPayouts[1] = PAYOUT_THRESHOLD_IBGT;
        baseTokenPayouts[2] = PAYOUT_THRESHOLD_NECT;

        feeManager = new FeeManager(
            FEE_RECIPIENT,
            TRADING_FEE_BPS,
            LISTING_FEE,
            MIGRATION_FEE_BPS
        );
        buzzTokenFactory = new BuzzTokenFactory(
            //TODO: check owner address
            address(this),
            createDeployer,
            address(feeManager)
        );
        referralManager = new ReferralManager(
            DIRECT_REF_FEE_BPS,
            INDIRECT_REF_FEE_BPS,
            VALID_UNTIL,
            baseTokens,
            baseTokenPayouts
        );
        bexLiquidityManager = new BexLiquidityManager(POOL_FACTORY, BEX_VAULT);
        buzzVaultExponential = new BuzzVaultExponential(
            address(feeManager),
            address(buzzTokenFactory),
            address(referralManager),
            address(bexLiquidityManager),
            address(wBERA)
        );
        highlightsManager = new HighlightsManager(
            FEE_RECIPIENT,
            HARD_CAP,
            HIGHLIGHTS_BASE_FEE,
            COOL_DOWN_PERIOD,
            "0x1bee"
        );
        tokenVesting = new TokenVesting();
    }

    function _initializeProtocol() internal {
        referralManager.setWhitelistedVault(
            address(buzzVaultExponential),
            true
        );
        buzzTokenFactory.setAllowedBaseToken(
            address(wBERA),
            BASE_TOKEN_MIN_RESERVE_AMOUNT,
            BASE_TOKEN_MIN_RAISE_AMOUNT,
            true
        );
        buzzTokenFactory.setAllowedBaseToken(
            address(iBGT),
            BASE_TOKEN_MIN_RESERVE_AMOUNT,
            BASE_TOKEN_MIN_RAISE_AMOUNT,
            true
        );
        buzzTokenFactory.setAllowedBaseToken(
            address(NECT),
            BASE_TOKEN_MIN_RESERVE_AMOUNT,
            BASE_TOKEN_MIN_RAISE_AMOUNT,
            true
        );
        buzzTokenFactory.setVault(address(buzzVaultExponential), true);
        buzzTokenFactory.setAllowTokenCreation(true);
        bexLiquidityManager.setVault(address(buzzVaultExponential));
    }

    function _deployTokens() internal {
        hevm.deal(address(this), LISTING_FEE * 3);
        address tokenOne = buzzTokenFactory.createToken{value: LISTING_FEE}(
            ["TOKEN 1", "T1"],
            [address(wBERA), address(buzzVaultExponential)],
            [uint256(1e18), uint256(1e36)],
            0,
            "0x1"
        );
        address tokenTwo = buzzTokenFactory.createToken{value: LISTING_FEE}(
            ["TOKEN 2", "T2"],
            [address(iBGT), address(buzzVaultExponential)],
            [uint256(1e18), uint256(1e36)],
            0,
            "0x2"
        );
        address tokenThree = buzzTokenFactory.createToken{value: LISTING_FEE}(
            ["TOKEN 3", "T3"],
            [address(NECT), address(buzzVaultExponential)],
            [uint256(10000e18), uint256(1e36)],
            0,
            "0x3"
        );

        quoteTokens.push(tokenOne);
        quoteTokens.push(tokenTwo);
        quoteTokens.push(tokenThree);
    }
}
