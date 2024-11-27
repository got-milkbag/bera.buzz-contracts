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
    /// @notice Error code emitted when the max initial buy is exceeded
    error BuzzToken_MaxInitialBuyExceeded();
    /// @notice Error code emitted when the market cap is under the minimum
    error BuzzToken_MarketCapUnderMin();
    /// @notice Error code emitted when the base amount is not enough to complete the autobuy transaction
    error BuzzToken_BaseAmountNotEnough();
    /// @notice Error code emitted when the base token address is not whitelisted
    error BuzzToken_BaseTokenNotWhitelisted();
    /// @notice Error code emitted when the value of K is not valid
    error BuzzToken_InvalidK();
    /// @notice Error code emitted when the value of growth rate is not valid
    error BuzzToken_InvalidGrowthRate();

    /// TODO: Fix indexed limit
    event TokenCreated(
        address indexed token,
        address baseToken,
        address indexed vault,
        address indexed deployer,
        string name,
        string symbol,
        uint256 marketCap
    );
    event VaultSet(address indexed vault, bool status);
    event TokenCreationSet(bool status);
    event FeeManagerSet(address indexed feeManager);
    event BaseTokenWhitelisted(address indexed baseToken, bool enabled);

    /// @notice The initial supply of the token
    uint256 public constant INITIAL_SUPPLY = 8e26;
    /// @notice The maximum initial deployer buy (5% of the total 1B supply)
    uint256 public constant MAX_INITIAL_BUY = 5e25;
    /// @notice The minimum market cap for a token
    uint256 public constant MIN_MARKET_CAP = 1e21;
    /// @notice The fee manager contract collecting the listing fee
    IFeeManager public feeManager;

    /// @dev access control owner role.
    bytes32 public immutable OWNER_ROLE;
    address public immutable CREATE_DEPLOYER;

    /// @notice Whether token creation is allowed. Controlled by accounts holding OWNER_ROLE.
    bool public allowTokenCreation;

    /// @notice A mapping of whitelisted vault addresses that can be used as vaults
    mapping(address => bool) public vaults;
    /// @notice A mapping of whitelisted base token addresses that can be used to deploy tokens
    mapping(address => bool) public whitelistedBaseTokens;
    /// @notice A mapping of deployed tokens via this factory
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
     * @param addr An address array containing the addresses for baseToken and vault
     * @param curveData An array containing the curve data for the token
     * @param baseAmount The amount of base token used to buy the new token after deployment
     * @param salt The salt for the CREATE3 deployment
     * @param marketCap The market cap of the token
     */
    function createToken(
        string[2] calldata metadata, //name, symbol
        address[2] calldata addr, //baseToken, vault
        uint256[2] calldata curveData, //k, growthRate
        uint256 baseAmount,
        bytes32 salt,
        uint256 marketCap
    ) external payable nonReentrant returns (address token) {
        if (!allowTokenCreation) revert BuzzToken_TokenCreationDisabled();
        if (!vaults[addr[1]]) revert BuzzToken_VaultNotRegistered();
        if (addr[0] == address(0)) revert BuzzToken_AddressZero();
        if (marketCap < MIN_MARKET_CAP) revert BuzzToken_MarketCapUnderMin();
        if (!whitelistedBaseTokens[addr[0]]) revert BuzzToken_BaseTokenNotWhitelisted();
        if (curveData[0] == 0) revert BuzzToken_InvalidK();
        if (curveData[1] == 0) revert BuzzToken_InvalidGrowthRate();

        uint256 listingFee = feeManager.listingFee();
        if (listingFee > 0) {
            if (msg.value < listingFee) revert BuzzToken_InsufficientFee();
            feeManager.collectListingFee{value: listingFee}();
        }

        emit TokenCreated(token, addr[0], addr[1], msg.sender, metadata[0], metadata[1], marketCap);
        token = _deployToken(metadata[0], metadata[1], addr[0], addr[1], salt, marketCap, curveData);

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
                IERC20(addr[0]).safeApprove(addr[1], baseAmount);
                IBuzzVault(addr[1]).buy(token, baseAmount, 1e15, address(0));
            }
            uint256 balanceAfter = IERC20(token).balanceOf(address(this));

            if (balanceAfter - balanceBefore > MAX_INITIAL_BUY) revert BuzzToken_MaxInitialBuyExceeded();
            IERC20(token).safeTransfer(msg.sender, balanceAfter - balanceBefore);
        }
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
     * @notice Enables or disables a base token address that can be used to deploy tokens
     * @param baseToken The address of the base token
     * @param enable True to whitelist, false to remove from the whitelist
     */
    function setAllowedBaseToken(address baseToken, bool enable) external onlyRole(OWNER_ROLE) {
        whitelistedBaseTokens[baseToken] = enable;

        emit BaseTokenWhitelisted(baseToken, enable);
    }

    /**
     * @notice Deploys a new token using CREATE3
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param baseToken The address of the base token
     * @param vault The address of the vault
     * @param salt The salt for the CREATE3 deployment
     * @param marketCap The market cap of the token
     * @return token The address of the deployed token
     */
    function _deployToken(
        string calldata name,
        string calldata symbol,
        address baseToken,
        address vault,
        bytes32 salt,
        uint256 marketCap,
        uint256[2] calldata curveData
    ) internal returns (address token) {
        uint256 k = curveData[0];
        uint256 growthRate = curveData[1];

        bytes memory bytecode = abi.encodePacked(type(BuzzToken).creationCode, abi.encode(name, symbol, INITIAL_SUPPLY, address(this), vault));

        token = ICREATE3Factory(CREATE_DEPLOYER).deploy(salt, bytecode);
        isDeployed[token] = true;

        IERC20(token).safeApprove(vault, INITIAL_SUPPLY);
        IBuzzVault(vault).registerToken(token, baseToken, INITIAL_SUPPLY, marketCap, k, growthRate);
    }
}
