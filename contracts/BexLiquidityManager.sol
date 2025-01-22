// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IBexLiquidityManager} from "./interfaces/IBexLiquidityManager.sol";
import {IWeightedPoolTokensFactory} from "./interfaces/bex/IWeightedPoolTokensFactory.sol";
import {IWeightedPoolTokens} from "./interfaces/bex/IWeightedPoolTokens.sol";
import {IVault} from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import {IAsset} from "@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";
import {IRateProvider} from "./interfaces/bex/IRateProvider.sol";

/**
 * @title BexLiquidityManager
 * @notice This contract migrated bonding curve liquidity to BEX
 * @author nexusflip, 0xMitzie
 */
contract BexLiquidityManager is Ownable, IBexLiquidityManager {
    using SafeERC20 for IERC20;

    /// @notice Event emitted when liquidity is migrated to BEX
    event BexListed(
        address indexed pool,
        address indexed baseToken,
        address indexed token,
        uint256 baseAmount,
        uint256 amount
    );
    /// @notice Event emitted when a vault is added to the whitelist
    event VaultAdded(address indexed vault);
    /// @notice Event emitted when a vault is removed from the whitelist
    event VaultRemoved(address indexed vault);

    /// @notice Error emitted when the caller is not authorized to perform the action
    error BexLiquidityManager_Unauthorized();
    /// @notice Error emitted when the vault is already in the whitelist
    error BexLiquidityManager_VaultAlreadyInWhitelist();
    /// @notice Error emitted when the vault is not in the whitelist
    error BexLiquidityManager_VaultNotInWhitelist();

    /// @notice The pool fee tier
    uint256 public constant POOL_FEE = 10000000000000000;

    /// @notice The WeightedPoolFactory contract
    IWeightedPoolTokensFactory public immutable POOL_FACTORY;
    /// @notice The Balancer Vault interface
    IVault public immutable VAULT;
    
    /// @notice The Vault address whitelist 
    mapping(address => bool) private vaults;

    /**
     * @notice Constructor a new BexLiquidityManager
     * @param _weightedPoolFactory The address of the WeightedPoolFactory contract
     * @param _vault The address of the Balancer Vault contract
     */
    constructor(address _weightedPoolFactory, address _vault) {
        POOL_FACTORY = IWeightedPoolTokensFactory(_weightedPoolFactory);
        VAULT = IVault(_vault);
    }

    /**
     * @notice Create a new pool with two erc20 tokens (base and quote tokens) in Bex and add liquidity to it.
     * @dev The caller must approve the contract to transfer both tokens.
     * @param token The address of the token to add
     * @param baseToken The address of the base token
     * @param baseAmount The amount of base tokens to add
     * @param amount The amount of tokens to add
     */
    function createPoolAndAdd(
        address token,
        address baseToken,
        uint256 baseAmount,
        uint256 amount
    ) external {
        if (!vaults[msg.sender]) revert BexLiquidityManager_Unauthorized();

        // Transfer and approve tokens
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(baseToken).safeTransferFrom(
            msg.sender,
            address(this),
            baseAmount
        );
        IERC20(token).safeApprove(address(VAULT), amount);
        IERC20(baseToken).safeApprove(address(VAULT), baseAmount);

        address base;
        address quote;

        if (baseToken < token) {
            base = baseToken;
            quote = token;
        } else {
            base = token;
            quote = baseToken;
        }

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(base);
        tokens[1] = IERC20(quote);

        uint256[] memory weights = new uint256[](2);
        weights[0] = 500000000000000000;
        weights[1] = 500000000000000000;

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProviders[0] = IRateProvider(address(0));
        rateProviders[1] = IRateProvider(address(0));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = baseAmount;
        amounts[1] = amount;

        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(base);
        assets[1] = IAsset(quote);

        // Create the pool
        address pool = POOL_FACTORY.create(
            string(abi.encodePacked("BEX 50 ", ERC20(base).symbol(), " 50 ", ERC20(quote).symbol())),
            string(abi.encodePacked("BEX-50", ERC20(base).symbol(), "-50", ERC20(quote).symbol())),
            tokens,
            weights,
            rateProviders,
            POOL_FEE,
            address(this),
            keccak256(abi.encodePacked(base, quote))
        );

        bytes32 poolId = IWeightedPoolTokens(pool).getPoolId();

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest(
            assets,
            amounts,
            abi.encode(amounts),
            false
        );

        // Deposit in the pool
        VAULT.joinPool(
            poolId,
            pool,
            address(this),
            request
        );

        // burn LP tokens - will use the conduit in the future for partnerships
        IERC20(pool).safeTransfer(
            address(0xdead),
            IERC20(pool).balanceOf(address(this))
        );

        // Emit event
        emit BexListed(pool, base, quote, baseAmount, amount);
    }

    /**
     * @notice Add a list of vaults to the whitelist
     * @param vault The array of vault addresses
     */
    function addVaults(address[] memory vault) external onlyOwner {
        uint256 vaultLength = vault.length;
        for (uint256 i; i < vaultLength; ++i) {
            if (vaults[vault[i]])
                revert BexLiquidityManager_VaultAlreadyInWhitelist();

            vaults[vault[i]] = true;
            emit VaultAdded(vault[i]);
        }
    }

    /**
     * @notice Remove a list of vaults from the whitelist
     * @param vault The array of vault addresses
     */
    function removeVaults(address[] calldata vault) external onlyOwner {
        uint256 vaultLength = vault.length;
        for (uint256 i; i < vaultLength; ++i) {
            if (!vaults[vault[i]])
                revert BexLiquidityManager_VaultNotInWhitelist();

            vaults[vault[i]] = false;
            emit VaultRemoved(vault[i]);
        }
    }
}
