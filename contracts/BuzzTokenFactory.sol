// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/create3/ICREATE3Factory.sol";

import "./BuzzToken.sol";
import "./interfaces/IBuzzTokenFactory.sol";
import "./interfaces/IBuzzVault.sol";
import "./interfaces/IFeeManager.sol";
import "hardhat/console.sol";

contract BuzzTokenFactory is AccessControl, ReentrancyGuard, IBuzzTokenFactory {
    using SafeERC20 for IERC20;

    /// @notice Error code emitted when token creation is disabled
    error BuzzToken_TokenCreationDisabled();
    /// @notice Error code emitted when the same bool is passed
    error BuzzToken_SameBool();
    /// @notice Error code emitted when the vault is not registered
    error BuzzToken_VaultNotRegistered();
    /// @notice Error code emitted when the address is zero
    error BuzzToken_AddressZero();
    /// @notice Error code emitted when the listing fee is insufficient
    error BuzzToken_InsufficientFee();
    /// @notice Error code emitted when the fee transfer failed
    error BuzzToken_FeeTransferFailed();
    /// @notice Error code emitted when the tax is too high
    error BuzzToken_TaxTooHigh();
    /// @notice Error code emitted when there is a tax address but 0 tax or vice versa
    error BuzzToken_TaxMismatch();
    /// @notice Error code emitted when the max initial buy is exceeded
    error BuzzToken_MaxInitialBuyExceeded();

    /// @notice Error code emitted when the base amount is not enough to complete the autobuy transaction
    error BuzzToken_BaseAmountNotEnough();

    /// TODO: Fix indexed limit
    event TokenCreated(
        address indexed token,
        address baseToken,
        address indexed vault,
        address indexed deployer,
        address taxTo,
        string name,
        string symbol,
        uint256 tax
    );
    event VaultSet(address indexed vault, bool status);
    event TokenCreationSet(bool status);
    event FeeManagerSet(address indexed feeManager);

    /// @notice The initial supply of the token
    uint256 public constant INITIAL_SUPPLY = 8e26;
    /// @notice The maximum tax rate in bps (10%)
    uint256 public constant MAX_TAX = 1000;
    /// @notice The maximum initial deployer buy (5% of the total 1B supply)
    uint256 public constant MAX_INITIAL_BUY = 5e25;
    /// @notice The fee manager contract collecting the listing fee
    IFeeManager public feeManager;

    /// @dev access control owner role.
    bytes32 public immutable OWNER_ROLE;
    address public immutable CREATE_DEPLOYER;

    /// @notice Whether token creation is allowed. Controlled by accounts holding OWNER_ROLE.
    bool public allowTokenCreation;

    mapping(address => bool) public vaults;
    mapping(address => bool) public isDeployed;

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
     * @param addr An address array containing the addresses for baseToken, vault, tax recipient
     * @param baseAmount The amount of base token used to buy the new token after deployment
     * @param salt The salt for the CREATE3 deployment
     * @param tax The tax rate in bps
     */
    function createToken(
        string[2] calldata metadata, //name, symbol
        address[3] calldata addr, //baseToken, vault, taxTo
        uint256 baseAmount,
        bytes32 salt,
        uint256 tax
    ) external payable nonReentrant returns (address token) {
        if (!allowTokenCreation) revert BuzzToken_TokenCreationDisabled();
        if (!vaults[addr[1]]) revert BuzzToken_VaultNotRegistered();
        if (addr[0] == address(0)) revert BuzzToken_AddressZero();
        if (tax > MAX_TAX) revert BuzzToken_TaxTooHigh();
        if ((addr[2] == address(0) && tax > 0) || (addr[2] != address(0) && tax == 0)) revert BuzzToken_TaxMismatch();

        uint256 listingFee = feeManager.listingFee();
        if (listingFee > 0) {
            if (msg.value < listingFee) revert BuzzToken_InsufficientFee();
            feeManager.collectListingFee{value: listingFee}();
        }
        token = _deployToken(metadata[0], metadata[1], addr[0], addr[1], addr[2], salt, tax);

        if (baseAmount > 0) {
            // Buy tokens after deployment
            uint256 balanceBefore = IERC20(token).balanceOf(address(this));
            if ((msg.value - listingFee) > 0) {
                // Buy tokens using excess msg.value. baseToken == wbera check occurs in Vault contract
                uint256 remainingValue = msg.value - listingFee;
                if (remainingValue != baseAmount) revert BuzzToken_BaseAmountNotEnough();
                IBuzzVault(addr[1]).buyNative{value: remainingValue}(token, 1e15, address(0));
            } else {
                // Buy tokens using base token
                IERC20(addr[0]).safeTransferFrom(msg.sender, address(this), baseAmount);
                IERC20(addr[0]).approve(addr[1], baseAmount);
                IBuzzVault(addr[1]).buy(token, baseAmount, 1e15, address(0));
            }
            uint256 balanceAfter = IERC20(token).balanceOf(address(this));

            if (balanceAfter - balanceBefore > MAX_INITIAL_BUY) revert BuzzToken_MaxInitialBuyExceeded();
            IERC20(token).safeTransfer(msg.sender, balanceAfter - balanceBefore);
        }

        emit TokenCreated(token, addr[0], addr[1], msg.sender, addr[2], metadata[0], metadata[1], tax);
    }

    /**
     * @notice Enables or disables a vault address that can be used to deploy tokens
     * @param _vault The address of the vault
     * @param enable The status of the vault
     */
    function setVault(address _vault, bool enable) external onlyRole(OWNER_ROLE) {
        if (_vault == address(0)) revert BuzzToken_AddressZero();
        if (vaults[_vault] == enable) revert BuzzToken_SameBool();
        vaults[_vault] = enable;

        emit VaultSet(_vault, enable);
    }

    /**
     * @notice Enables or disables token creation
     * @param _allowTokenCreation The status of token creation
     */
    function setAllowTokenCreation(bool _allowTokenCreation) external onlyRole(OWNER_ROLE) {
        if (allowTokenCreation == _allowTokenCreation) revert BuzzToken_SameBool();
        allowTokenCreation = _allowTokenCreation;

        emit TokenCreationSet(allowTokenCreation);
    }

    /**
     * @notice Sets the fee manager address
     * @param _feeManager The address of the fee manager contract
     */
    function setFeeManager(address payable _feeManager) external onlyRole(OWNER_ROLE) {
        feeManager = IFeeManager(_feeManager);

        emit FeeManagerSet(_feeManager);
    }

    /**
     * @notice Deploys a new token using CREATE3
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param vault The address of the vault
     * @param taxTo The address of the tax recipient
     * @param salt The salt for the CREATE3 deployment
     * @param tax The tax rate in bps
     * @return token The address of the deployed token
     */
    function _deployToken(
        string calldata name,
        string calldata symbol,
        address baseToken,
        address vault,
        address taxTo,
        bytes32 salt,
        uint256 tax
    ) internal returns (address token) {
        bytes memory bytecode = abi.encodePacked(
            type(BuzzToken).creationCode,
            abi.encode(name, symbol, INITIAL_SUPPLY, tax, address(this), taxTo, vault)
        );

        token = ICREATE3Factory(CREATE_DEPLOYER).deploy(salt, bytecode);
        isDeployed[token] = true;

        IERC20(token).safeApprove(vault, INITIAL_SUPPLY);
        IBuzzVault(vault).registerToken(token, baseToken, INITIAL_SUPPLY);
    }
}
