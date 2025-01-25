// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {BexLiquidityManager} from "../../contracts/BexLiquidityManager.sol";
import {BuzzTokenFactory} from "../../contracts/BuzzTokenFactory.sol";
import {BuzzVaultExponential} from "../../contracts/BuzzVaultExponential.sol";
import {FeeManager} from "../../contracts/FeeManager.sol";
import {HighlightsManager} from "../../contracts/HighlightsManager.sol";
import {ReferralManager} from "../../contracts/ReferralManager.sol";
import {TokenVesting} from "../../contracts/TokenVesting.sol";

import {ERC20Mock} from "../../test/invariant/mocks/ERC20Mock.sol";
import {WBERA} from "../../contracts/mock/WBERA.sol";

contract Base is Test {
    uint256 internal immutable _LISTING_FEE = 2e15;
    uint256 internal immutable _TRADING_FEE_BPS = 100;
    uint256 internal immutable _MIGRATION_FEE_BPS = 420;
    uint256 internal immutable _DIRECT_REF_FEE_BPS = 1500;
    uint256 internal immutable _INDIRECT_REF_FEE_BPS = 100;
    uint256 internal immutable _VALID_UNTIL = block.timestamp + 31536000;
    uint256 internal immutable _BASE_TOKEN_MIN_RESERVE_AMOUNT = 1e15;
    uint256 internal immutable _BASE_TOKEN_MIN_RAISE_AMOUNT = 1e18;
    uint256 internal immutable _HARD_CAP = 3600;
    uint256 internal immutable _HIGHLIGHTS_BASE_FEE = 5e14;
    uint256 internal immutable _COOL_DOWN_PERIOD = 86400;
    uint256 internal immutable _PAYOUT_THRESHOLD_WBERA = 0;
    uint256 internal immutable _PAYOUT_THRESHOLD_IBGT = 0;
    uint256 internal immutable _PAYOUT_THRESHOLD_NECT = 0;

    address internal immutable _CREATE3_DEPLOYER = 0xE088cf94c8C0200022E15e86fc4F9f3A4B2F6e5c;
    address internal immutable _BEX_POOL_FACTORY = 0x09836Ff4aa44C9b8ddD2f85683aC6846E139fFBf;
    address internal immutable _BEX_VAULT = 0x9C8a5c82e797e074Fe3f121B326b140CEC4bcb33;
    address internal immutable _TREASURY = makeAddr("_TREASURY");
    address internal immutable _OWNER = makeAddr("_OWNER");
    address internal immutable _USER = makeAddr("_USER");
    address internal immutable _ALICE = makeAddr("_ALICE");
    address internal immutable _BOB = makeAddr("_BOB");
    address internal immutable _ATTACKER = makeAddr("_ATTACKER");

    BexLiquidityManager internal bexLiquidityManager;
    BuzzTokenFactory internal buzzTokenFactory;
    BuzzVaultExponential internal buzzVaultExponential;
    FeeManager internal feeManager;
    HighlightsManager internal highlightsManager;
    ReferralManager internal referralManager;
    TokenVesting internal tokenVesting;

    WBERA internal wBERA;
    ERC20Mock internal iBGT;
    ERC20Mock internal NECT;

    modifier prank(address sender_) {
        vm.startPrank(sender_);
        _;
        vm.stopPrank();
    }

    function setUp() public {
        vm.createSelectFork("https://rockbeard-eth-cartio.berachain.com/");

        _deployBaseTokens();
        _deployProtocol();
        _configProtocol();
    }

    function _deployBaseTokens() private {
        wBERA = new WBERA();
        iBGT = new ERC20Mock("iBGT", "iBGT", 18);
        NECT = new ERC20Mock("NECT", "NECT", 18);
    }

    function _deployProtocol() private prank(_OWNER) {
        // Deploy the fee manager contract.
        feeManager = new FeeManager(_TREASURY, _TRADING_FEE_BPS, _LISTING_FEE, _MIGRATION_FEE_BPS);

        // Deploy the token factory contract.
        buzzTokenFactory = new BuzzTokenFactory(_OWNER, _CREATE3_DEPLOYER, address(feeManager));

        // Deploy the referral manager contract.
        address[] memory baseTokens = new address[](3);
        baseTokens[0] = address(wBERA);
        baseTokens[1] = address(iBGT);
        baseTokens[2] = address(NECT);
        uint256[] memory baseTokenPayouts = new uint256[](3);
        baseTokenPayouts[0] = _PAYOUT_THRESHOLD_WBERA;
        baseTokenPayouts[1] = _PAYOUT_THRESHOLD_IBGT;
        baseTokenPayouts[2] = _PAYOUT_THRESHOLD_NECT;
        referralManager =
            new ReferralManager(_DIRECT_REF_FEE_BPS, _INDIRECT_REF_FEE_BPS, _VALID_UNTIL, baseTokens, baseTokenPayouts);

        // Deploy the bex liquidity manager contract.
        bexLiquidityManager = new BexLiquidityManager(_BEX_POOL_FACTORY, _BEX_VAULT);

        // Deploy the exponential curve vault contract.
        buzzVaultExponential = new BuzzVaultExponential(
            address(feeManager),
            address(buzzTokenFactory),
            address(referralManager),
            address(bexLiquidityManager),
            address(wBERA)
        );

        // Deploy the highlights manager contract.
        highlightsManager =
            new HighlightsManager(payable(_OWNER), _HARD_CAP, _HIGHLIGHTS_BASE_FEE, _COOL_DOWN_PERIOD, "0x1bee");

        // Deploy the token vesting contract.
        tokenVesting = new TokenVesting();
    }

    function _configProtocol() private prank(_OWNER) {
        // Set the vault as whitelisted to allow the protocol to interact with the referral manager.
        referralManager.setWhitelistedVault(address(buzzVaultExponential), true);

        // Set wBERA as an allowed base token to be used as a reserve token.
        buzzTokenFactory.setAllowedBaseToken(
            address(wBERA), _BASE_TOKEN_MIN_RESERVE_AMOUNT, _BASE_TOKEN_MIN_RAISE_AMOUNT, true
        );

        // Set iBGT as an allowed base token to be used as a reserve token.
        buzzTokenFactory.setAllowedBaseToken(
            address(iBGT), _BASE_TOKEN_MIN_RESERVE_AMOUNT, _BASE_TOKEN_MIN_RAISE_AMOUNT, true
        );

        // Set NECT as an allowed base token to be used as a reserve token.
        buzzTokenFactory.setAllowedBaseToken(
            address(NECT), _BASE_TOKEN_MIN_RESERVE_AMOUNT, _BASE_TOKEN_MIN_RAISE_AMOUNT, true
        );

        // Set the exponential vault as whitelisted to allow the factory to create tokensfor specific bonding curves (vaults).
        buzzTokenFactory.setVault(address(buzzVaultExponential), true);

        // Allow the token factory to create tokens.
        buzzTokenFactory.setAllowTokenCreation(true);

        // Set the exponential vault to have permission to interact with the liquidity manager.
        address[] memory vaults = new address[](1);
        vaults[0] = address(buzzVaultExponential);
        bexLiquidityManager.addVaults(vaults);
    }
}
