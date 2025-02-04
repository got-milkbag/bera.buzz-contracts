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
 * @notice This contract migrates bonding curve liquidity to BEX
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
    /// @notice Event emitted when the Berabator contract address is set
    event BerabatorAddressSet(address indexed berabatorAddress);
    /// @notice Event emitted when a token is added to the Berabator whitelist
    event BerabatorWhitelistAdded(address indexed token);

    /// @notice Error emitted when the caller is not authorized to perform the action
    error BexLiquidityManager_Unauthorized();
    /// @notice Error emitted when the vault is already in the whitelist
    error BexLiquidityManager_VaultAlreadyInWhitelist();
    /// @notice Error emitted when the vault is not in the whitelist
    error BexLiquidityManager_VaultNotInWhitelist();
    /// @notice Error emitted when the Berabator address is not set
    error BexLiquidityManager_BerabatorAddressNotSet();
    /// @notice Error emitted when the token address is already whitelisted on Berabator
    error BexLiquidityManager_TokenAlreadyWhitelisted();
    /// @notice Error emitted when the address is zero
    error BexLiquidityManager_AddressZero();

    /**
     * @notice The memory params struct
     * @param amounts The array of amounts to deposit
     * @param weights The array of weights
     * @param tokens The array of IERC20 tokens
     * @param assets The array of IAsset token wrappers
     * @param rateProviders The array of rate providers
     * @param user The address of the user that triggered the migration
     */
    struct MemoryParams {
        uint256[] amounts;
        uint256[] weights;
        IERC20[] tokens;
        IAsset[] assets;
        IRateProvider[] rateProviders;
        address user;
    }

    /// @notice The WeightedPoolFactory contract
    IWeightedPoolFactory public immutable POOL_FACTORY;
    /// @notice The Balancer Vault interface
    IVault public immutable VAULT;

    /// @notice The pool fee tier (1%)
    uint256 public constant POOL_FEE = 10000000000000000;
    /// @notice The 50/50 weight
    uint256 public constant WEIGHT_50_50 = 500000000000000000;
    /// @notice The Berabator contract address
    address public berabatorAddress;

    /// @notice The Vault address whitelist
    mapping(address => bool) private vaults;
    /// @notice The Berabator whitelist
    mapping(address => bool) public berabatorWhitelist;

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
     * @param user The address of the user that triggered the migration
     * @param amount The amount of tokens to add
     * @param baseAmount The amount of base tokens to add
     * @return pool The address of the pool
     */
    function createPoolAndAdd(
        address token,
        address baseToken,
        address user,
        uint256 amount,
        uint256 baseAmount
    ) external returns (address pool) {
        if (!vaults[msg.sender]) revert BexLiquidityManager_Unauthorized();

        // Transfer and approve tokens
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(baseToken).safeTransferFrom(
            msg.sender,
            address(this),
            baseAmount
        );
        IERC20(token).forceApprove(address(VAULT), amount);
        IERC20(baseToken).forceApprove(address(VAULT), baseAmount);

        // Compute base and quote tokens
        (
            address quote,
            address base,
            uint256 convertedQuoteAmount,
            uint256 convertedBaseAmount
        ) = _computeBaseAndQuote(token, baseToken, amount, baseAmount);

        // Get memory params
        MemoryParams memory memoryParams = _getMemoryParams(
            quote,
            base,
            user,
            convertedQuoteAmount,
            convertedBaseAmount
        );

        // Create the pool and join
        pool = _createPoolAndJoin(memoryParams);
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
     * @notice Set the Berabator contract address
     * @param _berabatorAddress The address of the Berabator contract
     */
    function setBerabatorAddress(address _berabatorAddress) external onlyOwner {
        if (_berabatorAddress == address(0))
            revert BexLiquidityManager_AddressZero();

        berabatorAddress = _berabatorAddress;
        emit BerabatorAddressSet(_berabatorAddress);
    }

    /**
     * @notice Add a token to the Berabator whitelist
     * @param token The array of token addresses
     */
    function addBerabatorWhitelist(address token) external onlyOwner {
        if (berabatorAddress == address(0))
            revert BexLiquidityManager_BerabatorAddressNotSet();
        if (berabatorWhitelist[token])
            revert BexLiquidityManager_TokenAlreadyWhitelisted();

        berabatorWhitelist[token] = true;
        emit BerabatorWhitelistAdded(token);
    }

    /**
     * @notice Get the memory params
     * @param token The address of the token to add
     * @param baseToken The address of the base token
     * @param user The address of the user that triggered the migration
     * @param amount The amount of tokens to add
     * @param baseAmount The amount of base tokens to add
     * @return memoryParams The MemoryParams struct
     */
    function _getMemoryParams(
        address token,
        address baseToken,
        address user,
        uint256 amount,
        uint256 baseAmount
    ) private pure returns (MemoryParams memory memoryParams) {
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(baseToken);
        tokens[1] = IERC20(token);

        uint256[] memory weights = new uint256[](2);
        weights[0] = WEIGHT_50_50;
        weights[1] = weights[0];

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProviders[0] = IRateProvider(address(0));
        rateProviders[1] = rateProviders[0];

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = baseAmount;
        amounts[1] = amount;

        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(baseToken);
        assets[1] = IAsset(token);

        memoryParams = MemoryParams(
            amounts,
            weights,
            tokens,
            assets,
            rateProviders,
            user
        );
    }

    /**
     * @notice Compute the base and quote tokens
     * @param token The address of the token to add
     * @param baseToken The address of the base token
     * @param amount The amount of tokens to add
     * @param baseAmount The amount of base tokens to add
     * @return quote The address of the quote token
     * @return base The address of the base token
     * @return convertedQuoteAmount The converted amount of quote tokens
     * @return convertedBaseAmount The converted amount of base tokens
     */
    function _computeBaseAndQuote(
        address token,
        address baseToken,
        uint256 amount,
        uint256 baseAmount
    )
        private
        pure
        returns (
            address quote,
            address base,
            uint256 convertedQuoteAmount,
            uint256 convertedBaseAmount
        )
    {
        if (baseToken < token) {
            quote = token;
            base = baseToken;
            convertedQuoteAmount = amount;
            convertedBaseAmount = baseAmount;
        } else {
            quote = baseToken;
            base = token;
            convertedQuoteAmount = baseAmount;
            convertedBaseAmount = amount;
        }
    }

    /**
     * @notice Create a new pool with two erc20 tokens (base and quote tokens) in Bex and add liquidity to it.
     * @param memoryParams The MemoryParams struct
     * @return pool The address of the pool
     */
    function _createPoolAndJoin(
        MemoryParams memory memoryParams
    ) private returns (address pool) {
        // Create the pool
        pool = POOL_FACTORY.create(
            string(
                abi.encodePacked(
                    "BEX 50 ",
                    ERC20(address(memoryParams.tokens[0])).symbol(),
                    " 50 ",
                    ERC20(address(memoryParams.tokens[1])).symbol()
                )
            ),
            string(
                abi.encodePacked(
                    "BEX-50",
                    ERC20(address(memoryParams.tokens[0])).symbol(),
                    "-50",
                    ERC20(address(memoryParams.tokens[1])).symbol()
                )
            ),
            memoryParams.tokens,
            memoryParams.weights,
            memoryParams.rateProviders,
            POOL_FEE,
            address(this),
            keccak256(
                abi.encodePacked(
                    memoryParams.user,
                    block.timestamp,
                    address(memoryParams.tokens[0]),
                    address(memoryParams.tokens[1])
                )
            )
        );

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest(
            memoryParams.assets,
            memoryParams.amounts,
            abi.encode(0, memoryParams.amounts),
            false
        );

        // Deposit in the pool
        VAULT.joinPool(
            IWeightedPool(pool).getPoolId(),
            address(this),
            address(this),
            request
        );

        if (
            berabatorAddress != address(0) &&
            (berabatorWhitelist[address(memoryParams.tokens[0])] ||
                berabatorWhitelist[address(memoryParams.tokens[1])])
        ) {
            IERC20(pool).safeTransfer(
                berabatorAddress,
                IERC20(pool).balanceOf(address(this))
            );
        } else {
            IERC20(pool).safeTransfer(
                address(0xdead),
                IERC20(pool).balanceOf(address(this))
            );
        }

        // Emit event
        emit BexListed(
            pool,
            address(memoryParams.tokens[0]),
            address(memoryParams.tokens[1]),
            memoryParams.amounts[0],
            memoryParams.amounts[1]
        );
    }
}
