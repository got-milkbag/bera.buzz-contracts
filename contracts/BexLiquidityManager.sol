// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IBexLiquidityManager} from "./interfaces/IBexLiquidityManager.sol";
import {IWeightedPoolFactory} from "./interfaces/bex/IWeightedPoolFactory.sol";
import {IWeightedPool} from "./interfaces/bex/IWeightedPool.sol";
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

    /// @notice The pool fee tier (1%)
    uint256 public constant POOL_FEE = 10000000000000000;
    /// @notice The 50/50 weight
    uint256 public constant WEIGHT_50_50 = 500000000000000000;

    /// @notice The WeightedPoolFactory contract
    IWeightedPoolFactory public immutable POOL_FACTORY;
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
        POOL_FACTORY = IWeightedPoolFactory(_weightedPoolFactory);
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

        // Compute base and quote tokens
        (
            address base,
            address quote,
            uint256 convertedBaseAmount,
            uint256 convertedQuoteAmount
        ) = _computeBaseAndQuote(token, baseToken, baseAmount, amount);

        // Get memory params
        (
            IERC20[] memory tokens,
            uint256[] memory weights,
            IRateProvider[] memory rateProviders,
            uint256[] memory amounts,
            IAsset[] memory assets
        ) = _getMemoryParams(
                quote,
                base,
                convertedBaseAmount,
                convertedQuoteAmount
            );

        // Create the pool and join
        _createPoolAndJoin(tokens, weights, rateProviders, amounts, assets);
    }

    /**
     * @notice Add a list of vaults to the whitelist
     * @param vault The array of vault addresses
     */
    function addVaults(address[] memory vault) external onlyOwner {
        uint256 vaultLength = vault.length;
        for (uint256 i; i < vaultLength; ) {
            if (vaults[vault[i]])
                revert BexLiquidityManager_VaultAlreadyInWhitelist();

            vaults[vault[i]] = true;
            emit VaultAdded(vault[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Remove a list of vaults from the whitelist
     * @param vault The array of vault addresses
     */
    function removeVaults(address[] calldata vault) external onlyOwner {
        uint256 vaultLength = vault.length;
        for (uint256 i; i < vaultLength; ) {
            if (!vaults[vault[i]])
                revert BexLiquidityManager_VaultNotInWhitelist();

            vaults[vault[i]] = false;
            emit VaultRemoved(vault[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Get the memory params
     * @param token The address of the token to add
     * @param baseToken The address of the base token
     * @param baseAmount The amount of base tokens to add
     * @param amount The amount of tokens to add
     * @return tokens The array of IERC20 tokens
     * @return weights The array of weights
     * @return rateProviders The array of rate providers
     * @return amounts The array of amounts
     * @return assets The array of IAssets
     */
    function _getMemoryParams(
        address token,
        address baseToken,
        uint256 baseAmount,
        uint256 amount
    )
        private
        pure
        returns (
            IERC20[] memory tokens,
            uint256[] memory weights,
            IRateProvider[] memory rateProviders,
            uint256[] memory amounts,
            IAsset[] memory assets
        )
    {
        tokens = new IERC20[](2);
        tokens[0] = IERC20(baseToken);
        tokens[1] = IERC20(token);

        weights = new uint256[](2);
        weights[0] = WEIGHT_50_50;
        weights[1] = weights[0];

        rateProviders = new IRateProvider[](2);
        rateProviders[0] = IRateProvider(address(0));
        rateProviders[1] = rateProviders[0];

        amounts = new uint256[](2);
        amounts[0] = baseAmount;
        amounts[1] = amount;

        assets = new IAsset[](2);
        assets[0] = IAsset(baseToken);
        assets[1] = IAsset(token);
    }

    /**
     * @notice Compute the base and quote tokens
     * @param token The address of the token to add
     * @param baseToken The address of the base token
     * @param baseAmount The amount of base tokens to add
     * @param amount The amount of tokens to add
     * @return base The address of the base token
     * @return quote The address of the quote token
     * @return convertedBaseAmount The converted amount of base tokens
     * @return convertedQuoteAmount The converted amount of quote tokens
     */
    function _computeBaseAndQuote(
        address token,
        address baseToken,
        uint256 baseAmount,
        uint256 amount
    )
        private
        pure
        returns (
            address base,
            address quote,
            uint256 convertedBaseAmount,
            uint256 convertedQuoteAmount
        )
    {
        if (baseToken < token) {
            base = baseToken;
            quote = token;
            convertedBaseAmount = baseAmount;
            convertedQuoteAmount = amount;
        } else {
            base = token;
            quote = baseToken;
            convertedBaseAmount = amount;
            convertedQuoteAmount = baseAmount;
        }
    }

    /**
     * @notice Create a new pool with two erc20 tokens (base and quote tokens) in Bex and add liquidity to it.
     * @param tokens The array of token addresses to add
     * @param weights The array of weights
     * @param rateProviders The array of rate providers
     * @param amounts The array of amounts
     * @param assets The array of IAssets
     * @return pool The address of the pool
     */
    function _createPoolAndJoin(
        IERC20[] memory tokens,
        uint256[] memory weights,
        IRateProvider[] memory rateProviders,
        uint256[] memory amounts,
        IAsset[] memory assets
    ) private returns (address pool) {
        // Create the pool
        pool = POOL_FACTORY.create(
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
            rateProviders,
            POOL_FEE,
            address(this),
            keccak256(abi.encodePacked(address(tokens[0]), address(tokens[1])))
        );

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest(
            assets,
            amounts,
            abi.encode(0, amounts),
            false
        );

        // Deposit in the pool
        VAULT.joinPool(
            IWeightedPool(pool).getPoolId(),
            address(this),
            address(this),
            request
        );

        // burn LP tokens - will use the conduit in the future for partnerships
        IERC20(pool).safeTransfer(
            address(0xdead),
            IERC20(pool).balanceOf(address(this))
        );

        // Emit event
        emit BexListed(
            pool,
            address(tokens[0]),
            address(tokens[1]),
            amounts[0],
            amounts[1]
        );
    }
}
