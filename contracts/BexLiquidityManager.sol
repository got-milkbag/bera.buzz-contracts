// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IBexLiquidityManager.sol";
import "./interfaces/IWBera.sol";
import "./interfaces/bex/ICrocSwapDex.sol";
import "./libraries/SqrtMath.sol";
import "./bex/CrocLpErc20.sol";

contract BexLiquidityManager is IBexLiquidityManager {
    using SafeERC20 for IERC20;

    /// @notice Error code emitted when deposit to the WBera contract fails
    error WrappedDepositFailed();

    /// @notice Event emitted when liquidity is migrated to BEX
    event BexListed(address indexed token, uint256 beraAmount, uint256 initPrice);

    /// @notice The pool index to use when creating a pool (1% fee)
    uint256 private constant _poolIdx = 36002;
    /// @notice The amount of tokens to burn when adding liquidity
    uint256 private constant BURN_AMOUNT = 1e7;
    /// @notice The init code hash of the LP conduit
    bytes private constant LP_CONDUIT_INIT_CODE_HASH = hex"f8fb854b80d71035cc709012ce23accad9a804fcf7b90ac0c663e12c58a9c446";
    /// @notice The address of the wrapped Bera token
    IWBera public constant WBERA = IWBera(0x7507c1dc16935B82698e4C63f2746A2fCf994dF8);
    /// @notice The address of the CrocSwap DEX
    ICrocSwapDex public crocSwapDex;
    /// @notice The address of the LP conduit
    address public lpConduit;
    

    /**
     * @notice Constructor a new BexLiquidityManager
     * @param _crocSwapDex The address of the CrocSwap DEX
     */
    constructor(address _crocSwapDex) {
        crocSwapDex = ICrocSwapDex(_crocSwapDex);
    }

    /**
     * @notice Create a new pool with WBera and a specified token in Bex and add liquidity to it. Bera needs to be passed as msg.value
     * @dev The caller must approve the contract to transfer the token.
     * @param token The address of the token to add
     * @param amount The amount of tokens to add
     */
    function createPoolAndAdd(address token, uint256 amount) external payable {
        // Wrap Bera
        uint256 beraAmount = msg.value;
        WBERA.deposit{value: beraAmount}();

        // Transfer and approve tokens
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).safeApprove(address(crocSwapDex), amount);
        IERC20(address(WBERA)).safeApprove(address(crocSwapDex), beraAmount);

        address base;
        address quote;
        uint8 liqCode;

        if (address(WBERA) < token) {
            base = address(WBERA);
            quote = token;
            liqCode = 31; // Fixed liquidity based on base tokens
        } 
        else {
            base = token;
            quote = address(WBERA);
            liqCode = 32; // Fixed liquidity based on quote tokens
        }

        // Price should be in quote tokens per base token
        uint128 _initPrice = SqrtMath.encodePriceSqrt(amount, beraAmount);
        uint128 liquidity = uint128(beraAmount);

        lpConduit = _predictConduitAddress(base, quote);

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

        // Emit event
        emit BexListed(token, beraAmount, _initPrice);
    }

    /**
     * @notice Predict the address of the LP conduit for a given pair of tokens
     * @param base The address of the base token
     * @param quote The address of the quote token
     * @return lpConduit The address of the LP conduit
     */
    function _predictConduitAddress(address base, address quote) internal view returns (address) {
        bytes memory bytecode = type(CrocLpErc20).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(base, quote));
        
        address predictedAddress = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(crocSwapDex),
            salt,
            LP_CONDUIT_INIT_CODE_HASH
        )))));

        return predictedAddress;
    }
}
