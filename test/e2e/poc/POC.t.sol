// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Base} from "../Base.t.sol";

contract POC is Base {
    function test_poc_excess_native_token_not_reembursed() public {
        // Get the cost of the listing fee in the native token.
        uint256 listingFee = feeManager.listingFee();

        // Give twice the amount of the listing fee to the user.
        deal(_USER, listingFee * 2);

        // Create a new token via the factory.
        string[2] memory metadata;
        metadata[0] = "Memecoin";
        metadata[1] = "MEME";

        address[2] memory addr;
        addr[0] = address(wBERA);
        addr[1] = address(buzzVaultExponential);

        uint256[2] memory raiseData;
        raiseData[0] = 1e18;
        raiseData[1] = 1000e18;

        vm.prank(_USER);
        buzzTokenFactory.createToken{value: listingFee * 2}(metadata, addr, raiseData, 0, keccak256("MEME"));

        // Assert that the amount sent in excess is not reembursed.
        assertEq(_USER.balance, 0);

        // Assert that the treasury has only received the listing fee.
        assertEq(address(_TREASURY).balance, listingFee);

        // Assert that the remaning amount is locked in the factory forever.
        assertEq(address(buzzTokenFactory).balance, listingFee);
    }
}
