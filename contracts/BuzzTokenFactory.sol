// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/create3/ICREATE3Factory.sol";

import "./BuzzToken.sol";
import "./interfaces/IBuzzTokenFactory.sol";
import "./interfaces/IBuzzEventTracker.sol";
import "./interfaces/IBuzzVault.sol";

contract BuzzTokenFactory is AccessControl, IBuzzTokenFactory {
    using SafeERC20 for IERC20;

    /// @notice Error code emitted when token creation is disabled
    error BuzzToken_TokenCreationDisabled();
    /// @notice Error code emitted when the same bool is passed
    error BuzzToken_SameBool();
    /// @notice Error code emitted when the vault is not registered
    error BuzzToken_VaultNotRegistered();
    /// @notice Error code emitted when the address is zero
    error BuzzToken_AddressZero();

    event TokenCreated(address token);

    /// @dev access control owner role.
    uint256 public constant TOTAL_SUPPLY_OF_TOKENS = 1e27;

    bytes32 public immutable OWNER_ROLE;
    address public immutable CREATE_DEPLOYER;

    IBuzzEventTracker public immutable eventTracker;
    bool public allowTokenCreation;

    mapping(address => bool) public vaults;
    mapping(address => bool) public isDeployed;

    constructor(address _eventTracker, address _owner, address _createDeployer) {
        eventTracker = IBuzzEventTracker(_eventTracker);
        OWNER_ROLE = keccak256("OWNER_ROLE");
        _grantRole(OWNER_ROLE, _owner);
        CREATE_DEPLOYER = _createDeployer;
    }

    function createToken(
        string calldata name,
        string calldata symbol,
        string calldata description,
        string calldata image,
        address vault,
        bytes32 salt
    ) external returns (address token) {
        if (!allowTokenCreation) revert BuzzToken_TokenCreationDisabled();
        if (!vaults[vault]) revert BuzzToken_VaultNotRegistered();

        token = _deployToken(name, symbol, description, image, vault, salt);

        eventTracker.emitTokenCreated(token, name, symbol, description, image, msg.sender, vault);
        emit TokenCreated(token);
    }

    function setVault(address _vault, bool enable) external onlyRole(OWNER_ROLE) {
        if (_vault == address(0)) revert BuzzToken_AddressZero();
        vaults[_vault] = enable;
    }

    function setAllowTokenCreation(bool _allowTokenCreation) external onlyRole(OWNER_ROLE) {
        if (allowTokenCreation == _allowTokenCreation) revert BuzzToken_SameBool();
        allowTokenCreation = _allowTokenCreation;
    }

    function _deployToken(
        string calldata name,
        string calldata symbol,
        string calldata description,
        string calldata image,
        address vault,
        bytes32 salt
    ) internal returns (address token) {
        uint256 totalSupply = TOTAL_SUPPLY_OF_TOKENS;

        bytes memory bytecode =
            abi.encodePacked(
                type(BuzzToken).creationCode, 
                abi.encode(name, symbol, description, image, totalSupply, address(this))
            );
        
        isDeployed[token] = true;
        token = ICREATE3Factory(CREATE_DEPLOYER).deploy(salt, bytecode);

        IERC20(token).safeApprove(vault, totalSupply);
        IBuzzVault(vault).registerToken(token, totalSupply);
    }
}
