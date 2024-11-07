// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract BuzzToken is ERC20, AccessControl {
    event TaxedTransfer(address indexed from, address indexed to, uint256 amount, uint256 taxAmount);

    /// @dev The maximum tax rate in bps (10%)
    uint256 private constant MAX_TAX = 1000;
    /// @dev access control minter role.
    bytes32 public immutable MINTER_ROLE;
    /// @notice The tax rate in bps
    uint256 public immutable TAX;
    /// @notice The tax address receiving the tax. Defaults to address(0) if tax is 0.
    address public immutable TAX_ADDRESS;
    
    uint8 private constant DECIMALS = 18;

    constructor(
        string memory name,
        string memory symbol,
        uint256 _initialSupply,
        uint256 _tax,
        address mintTo,
        address taxTo,
        address _owner
    ) ERC20(name, symbol) {
        require(_tax <= MAX_TAX, "BuzzToken: tax exceeds MAX_TAX");
        
        TAX = _tax;
        _mint(mintTo, _initialSupply);

        MINTER_ROLE = keccak256("MINTER_ROLE");
        _grantRole(MINTER_ROLE, _owner);

        if (_tax > 0 && taxTo != address(0)) {
            TAX_ADDRESS = taxTo;
        }
        else {
            TAX_ADDRESS = address(0);
        }
    }

    function decimals() public pure override returns (uint8 _decimals) {
        _decimals = DECIMALS;
    }

    function mint(address account, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(account, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
        uint256 taxAmount = amount * TAX / 10000;
        uint256 amountAfterTax = amount - taxAmount;

        super._transfer(sender, recipient, amountAfterTax);
        
        if (TAX_ADDRESS != address(0) && taxAmount > 0) {
            super._transfer(sender, TAX_ADDRESS, taxAmount);
        }

        emit TaxedTransfer(sender, recipient, amount, taxAmount);
    }
}
