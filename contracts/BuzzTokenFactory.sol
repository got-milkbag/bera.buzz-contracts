// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BuzzToken} from "./BuzzToken.sol";
import {ICREATE3Factory} from "./interfaces/create3/ICREATE3Factory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBuzzTokenFactory} from "./interfaces/IBuzzTokenFactory.sol";
import {IBuzzVault} from "./interfaces/IBuzzVault.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";

/**
 * @title BuzzTokenFactory
 * @notice This contract is the factory for deploying new tokens
 * @author nexusflip, 0xMitzie
 */
contract BuzzTokenFactory is AccessControl, IBuzzTokenFactory {
    using SafeERC20 for IERC20;

    /// @notice Event emitted when a new token is created
    event TokenCreated(
        address indexed token,
        address indexed baseToken,
        address indexed vault,
        address deployer,
        string name,
        string symbol
    );
    /// @notice Event emitted when a vault address is enabled or disabled
    event VaultSet(address indexed vault, bool status);
    /// @notice Event emitted when token creation is enabled or disabled
    event TokenCreationSet(bool status);
    /// @notice Event emitted when the fee manager address is set
    event FeeManagerSet(address indexed feeManager);
    /// @notice Event emitted when a base token address is enabled or disabled
    event BaseTokenWhitelisted(
        address indexed baseToken,
        uint256 minReserveAmount,
        uint256 minRaiseAmount,
        bool enabled
    );

    /// @notice Error code emitted when token creation is disabled
    error BuzzToken_TokenCreationDisabled();
    /// @notice Error code emitted when the vault is not registered
    error BuzzToken_VaultNotRegistered();
    /// @notice Error code emitted when the address is zero
    error BuzzToken_AddressZero();
    /// @notice Error code emitted when the listing fee is insufficient
    error BuzzToken_InsufficientFee();
    /// @notice Error code emitted when the fee transfer failed
    error BuzzToken_FeeTransferFailed();
    /// @notice Error code emitted when the base amount is not enough to complete the autobuy transaction
    error BuzzToken_BaseAmountNotEnough();
    /// @notice Error code emitted when the base token address is not whitelisted
    error BuzzToken_BaseTokenNotWhitelisted();
    /// @notice Error code emitted when the initial reserves are invalid
    error BuzzToken_InvalidInitialReserves();
    /// @notice Error code emitted when the final reserves are invalid
    error BuzzToken_InvalidFinalReserves();
    /// @notice Error code emitted when the token name is invalid
    error BuzzToken_InvalidTokenName();
    /// @notice Error code emitted when the token symbol is invalid
    error BuzzToken_InvalidTokenSymbol();

    /**
     * @notice Struct containing the minimum reserve and raise amounts for a base token
     * @param minReserveAmount The minimum reserve amount
     * @param minRaiseAmount The minimum raise amount
     */
    struct RaiseInfo {
        uint256 minReserveAmount;
        uint256 minRaiseAmount;
    }

    /// @notice The fee manager contract collecting the listing fee
    IFeeManager public feeManager;

    /// @notice The initial supply of the token
    uint256 public constant INITIAL_SUPPLY = 1e27;
    /// @dev access control owner role.
    bytes32 public immutable OWNER_ROLE;
    /// @notice The address of the CREATE3 deployer
    address public immutable CREATE_DEPLOYER;
    /// @notice Whether token creation is allowed. Controlled by accounts holding OWNER_ROLE.
    bool public allowTokenCreation;

    /// @notice A mapping of whitelisted vault addresses that can be used as vaults
    mapping(address => bool) public vaults;
    /// @notice A mapping of whitelisted base token addresses that can be used to deploy tokens
    mapping(address => bool) public whitelistedBaseTokens;
    /// @notice A mapping of deployed tokens via this factory
    mapping(address => bool) public isDeployed;
    /// @notice A mapping of minimum reserve and raise amounts for a base token
    mapping(address => RaiseInfo) public raiseAmounts;

    /**
     * @notice Constructor of the Token Factory contract
     * @param _owner The owner of the contract
     * @param _createDeployer The address of the CREATE3 deployer
     * @param _feeManager The address of the feeManager contract
     */
    constructor(address _owner, address _createDeployer, address _feeManager) {
        OWNER_ROLE = keccak256("OWNER_ROLE");
        _grantRole(OWNER_ROLE, _owner);

        CREATE_DEPLOYER = _createDeployer;
        feeManager = IFeeManager(_feeManager);

        emit FeeManagerSet(_feeManager);
    }

    /**
     * @notice Deploys a new token
     * @dev Msg.value should be greater or equal to the listing fee.
     * @param metadata A string array containing the name and symbol of the token
     * @param addr An address array containing the addresses for baseToken and vault
     * @param raiseData An array containing the reserve data for the token
     * @param baseAmount The amount of base token used to buy the new token after deployment
     * @param salt The salt for the CREATE3 deployment
     */
    function createToken(
        string[2] calldata metadata, //name, symbol
        address[2] calldata addr, //baseToken, vault
        uint256[2] calldata raiseData, //initialReserves, finalReserves
        uint256 baseAmount,
        bytes32 salt
    ) external payable returns (address token) {
        if (!allowTokenCreation) revert BuzzToken_TokenCreationDisabled();
        if (addr[0] == address(0)) revert BuzzToken_AddressZero();
        if (!vaults[addr[1]]) revert BuzzToken_VaultNotRegistered();
        if (bytes(metadata[0]).length == 0) revert BuzzToken_InvalidTokenName();
        if (bytes(metadata[1]).length == 0)
            revert BuzzToken_InvalidTokenSymbol();
        if (!whitelistedBaseTokens[addr[0]])
            revert BuzzToken_BaseTokenNotWhitelisted();
        if (raiseData[0] < raiseAmounts[addr[0]].minReserveAmount)
            revert BuzzToken_InvalidInitialReserves();
        if (raiseData[1] < raiseData[0] + raiseAmounts[addr[0]].minRaiseAmount)
            revert BuzzToken_InvalidFinalReserves();

        uint256 listingFee = feeManager.listingFee();
        if (listingFee > 0) {
            if (msg.value < listingFee) revert BuzzToken_InsufficientFee();
            feeManager.collectListingFee{value: listingFee}();
        }

        token = _deployToken(
            metadata[0],
            metadata[1],
            addr[0],
            addr[1],
            salt,
            raiseData
        );
        emit TokenCreated(
            token,
            addr[0],
            addr[1],
            msg.sender,
            metadata[0],
            metadata[1]
        );

        if (baseAmount > 0) {
            if ((msg.value - listingFee) > 0) {
                // Buy tokens using excess msg.value. baseToken == wbera check occurs in Vault contract
                uint256 remainingValue = msg.value - listingFee;
                if (remainingValue != baseAmount)
                    revert BuzzToken_BaseAmountNotEnough();
                IBuzzVault(addr[1]).buyNative{value: remainingValue}(
                    token,
                    1e15,
                    address(0),
                    msg.sender
                );
            } else {
                // Buy tokens using base token
                IERC20(addr[0]).safeTransferFrom(
                    msg.sender,
                    address(this),
                    baseAmount
                );
                IERC20(addr[0]).safeApprove(addr[1], baseAmount);
                IBuzzVault(addr[1]).buy(
                    token,
                    baseAmount,
                    1e15,
                    address(0),
                    msg.sender
                );
            }
        }
    }

    /**
     * @notice Enables or disables a vault address that can be used to deploy tokens
     * @param vault The address of the vault
     * @param enable The status of the vault
     */
    function setVault(
        address vault,
        bool enable
    ) external onlyRole(OWNER_ROLE) {
        if (vault == address(0)) revert BuzzToken_AddressZero();

        vaults[vault] = enable;
        emit VaultSet(vault, enable);
    }

    /**
     * @notice Enables or disables token creation
     * @param allowTokenCreation_ The status of token creation
     */
    function setAllowTokenCreation(
        bool allowTokenCreation_
    ) external onlyRole(OWNER_ROLE) {
        allowTokenCreation = allowTokenCreation_;

        emit TokenCreationSet(allowTokenCreation);
    }

    /**
     * @notice Sets the fee manager address
     * @param feeManager_ The address of the fee manager contract
     */
    function setFeeManager(
        address payable feeManager_
    ) external onlyRole(OWNER_ROLE) {
        if (feeManager_ == address(0)) revert BuzzToken_AddressZero();

        feeManager = IFeeManager(feeManager_);
        emit FeeManagerSet(feeManager_);
    }

    /**
     * @notice Enables or disables a base token address that can be used to deploy tokens
     * @param baseToken The address of the base token
     * @param minReserveAmount The minimum reserve amount
     * @param minRaiseAmount The minimum raise amount
     * @param enable True to whitelist, false to remove from the whitelist
     */
    function setAllowedBaseToken(
        address baseToken,
        uint256 minReserveAmount,
        uint256 minRaiseAmount,
        bool enable
    ) external onlyRole(OWNER_ROLE) {
        if (baseToken == address(0)) revert BuzzToken_AddressZero();

        if (
            raiseAmounts[baseToken].minReserveAmount == 0 &&
            raiseAmounts[baseToken].minRaiseAmount == 0
        ) {
            raiseAmounts[baseToken] = RaiseInfo(
                minReserveAmount,
                minRaiseAmount
            );
        } else {
            raiseAmounts[baseToken].minReserveAmount = minReserveAmount;
            raiseAmounts[baseToken].minRaiseAmount = minRaiseAmount;
        }
        whitelistedBaseTokens[baseToken] = enable;

        emit BaseTokenWhitelisted(
            baseToken,
            minReserveAmount,
            minRaiseAmount,
            enable
        );
    }

    /**
     * @notice Deploys a new token using CREATE3
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param baseToken The address of the base token
     * @param vault The address of the vault
     * @param salt The salt for the CREATE3 deployment
     * @param raiseData An array containing the reserve data for the token
     * @return token The address of the deployed token
     */
    function _deployToken(
        string calldata name,
        string calldata symbol,
        address baseToken,
        address vault,
        bytes32 salt,
        uint256[2] calldata raiseData
    ) internal returns (address token) {
        uint256 initialReserves = raiseData[0];
        uint256 finalReserves = raiseData[1];
        uint256 initialSupply = INITIAL_SUPPLY;

        bytes memory bytecode = abi.encodePacked(
            type(BuzzToken).creationCode,
            abi.encode(name, symbol, initialSupply, address(this), vault)
        );

        token = ICREATE3Factory(CREATE_DEPLOYER).getDeployed(
            address(this),
            salt
        );
        isDeployed[token] = true;

        ICREATE3Factory(CREATE_DEPLOYER).deploy(salt, bytecode);

        IERC20(token).safeApprove(vault, initialSupply);
        IBuzzVault(vault).registerToken(
            token,
            baseToken,
            initialSupply,
            initialReserves,
            finalReserves
        );
    }
}
