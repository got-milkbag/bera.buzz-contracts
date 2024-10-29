// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/create3/ICREATE3Factory.sol";

import "./BuzzToken.sol";
import "./interfaces/IBuzzTokenFactory.sol";
import "./interfaces/IBuzzEventTracker.sol";
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
    /// @notice Error code emitted when the tax is too high
    error BuzzToken_TaxTooHigh();
    /// @notice Error code emitted when there is a tax address but 0 tax or vice versa
    error BuzzToken_TaxMismatch();

    event TokenCreated(address indexed token);
    event VaultSet(address indexed vault, bool status);
    event TokenCreationSet(bool status);
    event ListingFeeSet(uint256 fee);
    event TreasurySet(address indexed treasury);

    /// @notice The initial supply of the token
    uint256 public constant INITIAL_SUPPLY = 8e26;
    /// @notice The maximum tax rate in bps (10%)
    uint256 public constant MAX_TAX = 1000;
    /// @notice The fee that needs to be paid to deploy a token, in wei.
    uint256 public listingFee;
    /// @notice The treasury address collecting the listing fee
    address payable public treasury;

    /// @dev access control owner role.
    bytes32 public immutable OWNER_ROLE;
    address public immutable CREATE_DEPLOYER;

    /// @notice The address of the event tracker contract
    IBuzzEventTracker public immutable eventTracker;
    /// @notice Whether token creation is allowed. Controlled by accounts holding OWNER_ROLE.
    bool public allowTokenCreation;

    mapping(address => bool) public vaults;
    mapping(address => bool) public isDeployed;

    constructor(address _eventTracker, address _owner, address _createDeployer, address _treasury, uint256 _listingFee) {
        eventTracker = IBuzzEventTracker(_eventTracker);
        OWNER_ROLE = keccak256("OWNER_ROLE");
        _grantRole(OWNER_ROLE, _owner);

        CREATE_DEPLOYER = _createDeployer;
        treasury = payable(_treasury);
        listingFee = _listingFee;
    }

    function createToken(
        string calldata name,
        string calldata symbol,
        address vault,
        address taxTo,
        bytes32 salt,
        uint256 tax
    ) external payable nonReentrant returns (address token) {
        if (!allowTokenCreation) revert BuzzToken_TokenCreationDisabled();
        if (!vaults[vault]) revert BuzzToken_VaultNotRegistered();
        if (msg.value < listingFee) revert BuzzToken_InsufficientFee();
        if (tax > MAX_TAX) revert BuzzToken_TaxTooHigh();
        if ((taxTo == address(0) && tax > 0) || (taxTo != address(0) && tax == 0)) revert BuzzToken_TaxMismatch();

        _transferFee(listingFee);
        token = _deployToken(name, symbol, vault, taxTo, salt, tax);

        eventTracker.emitTokenCreated(token, name, symbol, msg.sender, vault, tax);
        emit TokenCreated(token);

        if ((msg.value - listingFee) > 0) {
            uint256 balanceBefore = IERC20(token).balanceOf(address(this));
            IBuzzVault(vault).buy{value: msg.value - listingFee}(token, 1e15, address(0));
            uint256 balanceAfter = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransfer(msg.sender, balanceAfter - balanceBefore);
        }
    }

    function setVault(address _vault, bool enable) external onlyRole(OWNER_ROLE) {
        if (_vault == address(0)) revert BuzzToken_AddressZero();
        if (vaults[_vault] == enable) revert BuzzToken_SameBool();
        vaults[_vault] = enable;

        emit VaultSet(_vault, enable);
    }

    function setAllowTokenCreation(bool _allowTokenCreation) external onlyRole(OWNER_ROLE) {
        if (allowTokenCreation == _allowTokenCreation) revert BuzzToken_SameBool();
        allowTokenCreation = _allowTokenCreation;

        emit TokenCreationSet(allowTokenCreation);
    }

    function setTreasury(address payable _treasury) external onlyRole(OWNER_ROLE) {
        treasury = _treasury;

        emit TreasurySet(_treasury);
    }

    function setListingFee(uint256 _listingFee) external onlyRole(OWNER_ROLE) {
        listingFee = _listingFee;

        emit ListingFeeSet(_listingFee);
    }

    function _deployToken(
        string calldata name,
        string calldata symbol,
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
        IBuzzVault(vault).registerToken(token, INITIAL_SUPPLY);
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
