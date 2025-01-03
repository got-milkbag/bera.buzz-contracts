// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IBexLiquidityManager.sol";
import "./interfaces/bex/ICrocSwapDex.sol";
import "./libraries/SqrtMath.sol";
import "./bex/CrocLpErc20.sol";

contract BexLiquidityManager is Ownable, IBexLiquidityManager {
    using SafeERC20 for IERC20;

    /// @notice Error emitted when the caller is not authorized to perform the action
    error BexLiquidityManager_Unauthorized();
    /// @notice Error emitted when the vault is already in the whitelist
    error BexLiquidityManager_VaultAlreadyInWhitelist();
    /// @notice Error emitted when the vault is not in the whitelist
    error BexLiquidityManager_VaultNotInWhitelist();

    /// @notice Event emitted when liquidity is migrated to BEX
    event BexListed(address indexed token, uint256 beraAmount, uint256 initPrice, address lpConduit);
    /// @notice Event emitted when a vault is added to the whitelist
    event VaultAdded(address indexed vault);
    /// @notice Event emitted when a vault is removed from the whitelist
    event VaultRemoved(address indexed vault);

    /// @notice The pool index to use when creating a pool (1% fee)
    uint256 private constant _poolIdx = 36002;
    /// @notice The amount of tokens to burn when adding liquidity
    uint256 private constant BURN_AMOUNT = 1e7;
    /// @notice The init code hash of the LP conduit
    bytes private constant LP_CONDUIT_INIT_CODE_HASH = hex"f8fb854b80d71035cc709012ce23accad9a804fcf7b90ac0c663e12c58a9c446";
    /// @notice The address of the CrocSwap DEX
    ICrocSwapDex private immutable crocSwapDex;
    /// @notice The Vault address whitelist
    mapping(address => bool) private vaults;

    /**
     * @notice Constructor a new BexLiquidityManager
     * @param _crocSwapDex The address of the CrocSwap DEX
     */
    constructor(address _crocSwapDex) {
        crocSwapDex = ICrocSwapDex(_crocSwapDex);
    }

    /**
     * @notice Create a new pool with two erc20 tokens (base and quote tokens) in Bex and add liquidity to it.
     * @dev The caller must approve the contract to transfer both tokens.
     * @param token The address of the token to add
     * @param baseToken The address of the base token
     * @param baseAmount The amount of base tokens to add
     * @param amount The amount of tokens to add
     */
    function createPoolAndAdd(address token, address baseToken, uint256 baseAmount, uint256 amount) external {
        if(!vaults[msg.sender]) revert BexLiquidityManager_Unauthorized();

        // Transfer and approve tokens
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(baseToken).safeTransferFrom(msg.sender, address(this), baseAmount);
        IERC20(token).safeApprove(address(crocSwapDex), amount);
        IERC20(baseToken).safeApprove(address(crocSwapDex), baseAmount);

        address base;
        address quote;
        uint8 liqCode;

        if (baseToken < token) {
            base = baseToken;
            quote = token;
            liqCode = 31; // Fixed liquidity based on base tokens
        } else {
            base = token;
            quote = baseToken;
            liqCode = 32; // Fixed liquidity based on quote tokens
        }

        // Price should be in quote tokens per base token
        uint128 _initPrice = SqrtMath.encodePriceSqrt(amount, baseAmount);
        uint128 liquidity = uint128(baseAmount);

        address lpConduit = _predictConduitAddress(base, quote);

        // Create pool
        // initPool subcode, base, quote, poolIdx, price ins q64.64
        bytes memory cmd1 = abi.encode(71, base, quote, _poolIdx, _initPrice);

        // Add liquidity
        // liquidity subcode (fixed in base tokens, fill-range liquidity)
        // liq subcode, base, quote, poolIdx, bid tick, ask tick, liquidity, lower limit, upper limit, res flags, lp conduit
        // because Bex burns a small insignificant amount of tokens, we reduce the liquidity by BURN_AMOUNT
        // any token dust will be burned and any BERA dust shall be sent back to the treasury or to the user that triggered the migration as a reward
        bytes memory cmd2 = abi.encode(liqCode, base, quote, _poolIdx, 0, 0, liquidity - BURN_AMOUNT, _initPrice, _initPrice, 0, lpConduit);

        // Encode commands into a multipath call
        bytes memory encodedCmd = abi.encode(2, 3, cmd1, 128, cmd2);

        // Execute multipath call
        crocSwapDex.userCmd(6, encodedCmd);

        // burn LP tokens - will use the conduit in the future for partnerships
        IERC20(lpConduit).safeTransfer(address(0x1), IERC20(lpConduit).balanceOf(address(this)));

        // Emit event
        emit BexListed(token, baseAmount, _initPrice, lpConduit);
    }

    /**
     * @notice Add a list of vaults to the whitelist
     * @param vault The array of vault addresses
     */
    function addVaults(address[] memory vault) external onlyOwner {
        for (uint256 i; i < vault.length;) {
            if (vaults[vault[i]]) revert BexLiquidityManager_VaultAlreadyInWhitelist();
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
        for (uint256 i; i < vault.length;) {
            if (!vaults[vault[i]]) revert BexLiquidityManager_VaultNotInWhitelist();
            vaults[vault[i]] = false;

            emit VaultRemoved(vault[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Predict the address of the LP conduit for a given pair of tokens
     * @param base The address of the base token
     * @param quote The address of the quote token
     * @return lpConduit The address of the LP conduit
     */
    function _predictConduitAddress(address base, address quote) internal view returns (address lpConduit) {
        bytes memory bytecode = type(CrocLpErc20).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(base, quote));

        lpConduit = address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(crocSwapDex), salt, LP_CONDUIT_INIT_CODE_HASH)))));
    }
}
