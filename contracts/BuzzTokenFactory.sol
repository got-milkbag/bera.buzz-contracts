// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CREATE3} from "solmate/src/utils/CREATE3.sol";

import "./BuzzToken.sol";
import "./interfaces/IBuzzVault.sol";
import "./interfaces/IBuzzEventTracker.sol";

contract BuzzTokenFactory is AccessControl {
    error BuzzToken_TokenCreationDisabled();
    error BuzzToken_InvalidParams();

    event TokenCreated(address token);

    /// @dev access control owner role.
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    IBuzzEventTracker public eventTracker;
    bool public allowTokenCreation;
    uint256 public constant totalSupplyOfTokens = 1000000000000000000000000000;

    mapping(address => bool) public vaults;
    mapping(address => bool) public isDeployed;

    constructor(address _eventTracker, address _owner) {
        eventTracker = IBuzzEventTracker(_eventTracker);
        _grantRole(OWNER_ROLE, _owner);
    }

    function createToken(
        string memory name,
        string memory symbol,
        string memory description,
        string memory image,
        address vault,
        bytes32 salt
    ) public returns (address) {
        if (!allowTokenCreation) revert BuzzToken_TokenCreationDisabled();
        if (vaults[vault] == false) revert BuzzToken_InvalidParams();

        address token = _deployToken(name, symbol, description, image, vault, salt);

        eventTracker.emitTokenCreated(token, name, symbol, description, image, msg.sender, vault);
        emit TokenCreated(token);

        return address(token);
    }

    function setVault(address _vault, bool enable) public onlyRole(OWNER_ROLE) {
        if (_vault == address(0)) revert BuzzToken_InvalidParams();
        vaults[_vault] = enable;
    }

    function setAllowTokenCreation(bool _allowTokenCreation) public onlyRole(OWNER_ROLE) {
        allowTokenCreation = _allowTokenCreation;
    }

    function _deployToken(
        string memory name,
        string memory symbol,
        string memory description,
        string memory image,
        address vault,
        bytes32 salt
    ) internal returns (address token) {
        bytes memory bytecode =
            abi.encodePacked(
                type(BuzzToken).creationCode, 
                abi.encode(name, symbol, description, image, totalSupplyOfTokens, address(this))
            );

        token = CREATE3.deploy(salt, bytecode, 0);

        IERC20(token).approve(vault, totalSupplyOfTokens);
        IBuzzVault(vault).registerToken(token, totalSupplyOfTokens);
        isDeployed[token] = true;
    }
}
