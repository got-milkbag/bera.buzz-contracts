// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/create3/ICREATE3Factory.sol";

import "./BuzzToken.sol";
import "./interfaces/IBuzzVault.sol";
import "./interfaces/IBuzzEventTracker.sol";

contract BuzzTokenFactory is AccessControl {
    error BuzzToken_TokenCreationDisabled();
    error BuzzToken_InvalidParams();

    event TokenCreated(address token);

    /// @dev access control owner role.
    uint256 public constant TOTAL_SUPPLY_OF_TOKENS = 1000000000000000000000000000;
    bytes32 public immutable OWNER_ROLE;
    address public immutable CREATE_DEPLOYER;

    IBuzzEventTracker public eventTracker;
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
    ) external returns (address) {
        if (!allowTokenCreation) revert BuzzToken_TokenCreationDisabled();
        if (vaults[vault] == false) revert BuzzToken_InvalidParams();

        address token = _deployToken(name, symbol, description, image, vault, salt);

        eventTracker.emitTokenCreated(token, name, symbol, description, image, msg.sender, vault);
        emit TokenCreated(token);

        return address(token);
    }

    function setVault(address _vault, bool enable) external onlyRole(OWNER_ROLE) {
        if (_vault == address(0)) revert BuzzToken_InvalidParams();
        vaults[_vault] = enable;
    }

    function setAllowTokenCreation(bool _allowTokenCreation) external onlyRole(OWNER_ROLE) {
        if (allowTokenCreation == _allowTokenCreation) revert BuzzToken_InvalidParams();
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
        bytes memory bytecode =
            abi.encodePacked(
                type(BuzzToken).creationCode, 
                abi.encode(name, symbol, description, image, TOTAL_SUPPLY_OF_TOKENS, address(this))
            );

        token = ICREATE3Factory(CREATE_DEPLOYER).deploy(salt, bytecode);

        isDeployed[token] = true;

        IERC20(token).approve(vault, TOTAL_SUPPLY_OF_TOKENS);
        IBuzzVault(vault).registerToken(token, TOTAL_SUPPLY_OF_TOKENS);
    }
}
