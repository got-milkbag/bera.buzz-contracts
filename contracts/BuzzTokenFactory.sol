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

    event TokenCreated(
        address indexed token, 
        address indexed vault, 
        address indexed deployer, 
        string name, 
        string symbol
    );
    event VaultSet(address indexed vault, bool status);
    event TokenCreationSet(bool status);
    event ListingFeeSet(uint256 fee);
    event TreasurySet(address indexed treasury);

    uint256 public constant TOTAL_SUPPLY_OF_TOKENS = 1e27;
    /// @notice The fee that needs to be paid to deploy a token, in wei.
    uint256 public listingFee;
    /// @notice The treasury address collecting the listing fee
    address payable public treasury;

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
     * @param _tresury The address of the treasury
     * @param _listingFee The fee to deploy a token
     */
    constructor(address _owner, address _createDeployer, address _tresury, uint256 _listingFee) {
        OWNER_ROLE = keccak256("OWNER_ROLE");
        _grantRole(OWNER_ROLE, _owner);
        CREATE_DEPLOYER = _createDeployer;
        treasury = payable(_tresury);
        listingFee = _listingFee;
    }

    /**
     * @notice Deploys a new token
     * @dev Msg.value should be greater or equal to the listing fee
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param vault The address of the vault
     * @param salt The salt for the CREATE3 deployment
     */
    function createToken(
        string calldata name,
        string calldata symbol,
        address vault,
        bytes32 salt
    ) external payable nonReentrant returns (address token) {
        if (!allowTokenCreation) revert BuzzToken_TokenCreationDisabled();
        if (!vaults[vault]) revert BuzzToken_VaultNotRegistered();
        if (msg.value < listingFee) revert BuzzToken_InsufficientFee();

        _transferFee(listingFee);
        token = _deployToken(name, symbol, vault, salt);

        if ((msg.value - listingFee) > 0) {
            uint256 balanceBefore = IERC20(token).balanceOf(address(this));
            IBuzzVault(vault).buy{value: msg.value - listingFee}(token, 1e15, address(0));
            uint256 balanceAfter = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransfer(msg.sender, balanceAfter - balanceBefore);
        }

        emit TokenCreated(token, vault, msg.sender, name, symbol);
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
     * @notice Sets the treasury address
     * @param _treasury The address of the treasury
     */
    function setTreasury(address payable _treasury) external onlyRole(OWNER_ROLE) {
        treasury = _treasury;

        emit TreasurySet(_treasury);
    }

    /**
     * @notice Sets the listing fee
     * @param _listingFee The fee to deploy a token
     */
    function setListingFee(uint256 _listingFee) external onlyRole(OWNER_ROLE) {
        listingFee = _listingFee;

        emit ListingFeeSet(_listingFee);
    }

    /**
     * @notice Deploys a new token using CREATE3
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param vault The address of the vault
     * @param salt The salt for the CREATE3 deployment
     * @return token The address of the deployed token
     */
    function _deployToken(string calldata name, string calldata symbol, address vault, bytes32 salt) internal returns (address token) {
        uint256 totalSupply = TOTAL_SUPPLY_OF_TOKENS;

        bytes memory bytecode = abi.encodePacked(type(BuzzToken).creationCode, abi.encode(name, symbol, totalSupply, address(this)));

        token = ICREATE3Factory(CREATE_DEPLOYER).deploy(salt, bytecode);
        isDeployed[token] = true;

        IERC20(token).safeApprove(vault, totalSupply);
        IBuzzVault(vault).registerToken(token, totalSupply);
    }

    /**
     * @notice Transfers bera to the treasury, checking if the transfer was successful
     * @param amount The amount to transfer
     */
    function _transferFee(uint256 amount) internal {
        (bool success, ) = treasury.call{value: amount}("");
        if (!success) revert BuzzToken_FeeTransferFailed();
    }
}
