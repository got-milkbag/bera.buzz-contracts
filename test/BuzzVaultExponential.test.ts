import {expect} from "chai";
import {ethers} from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {Contract} from "ethers";

describe("BuzzVaultExponential Tests", () => {
    let ownerSigner: SignerWithAddress;
    let user1Signer: SignerWithAddress;
    let user2Signer: SignerWithAddress;
    let factory: Contract;
    let vault: Contract;
    let token: Contract;

    beforeEach(async () => {
        [ownerSigner, user1Signer, user2Signer] = await ethers.getSigners();

        // Deploy factory
        const Factory = await ethers.getContractFactory("BuzzTokenFactory");
        factory = await Factory.connect(ownerSigner).deploy();

        // Deploy Vault
        const Vault = await ethers.getContractFactory("BuzzVaultExponential");
        vault = await Vault.connect(ownerSigner).deploy(factory.address, ethers.constants.AddressZero);

        // Admin: Set Vault as the factory's vault & enable token creation
        await factory.connect(ownerSigner).setVault(vault.address, true);
        await factory.connect(ownerSigner).setAllowTokenCreation(true);

        // Create a token
        const tx = await factory.createToken("TEST", "TEST", vault.address);
        const receipt = await tx.wait();
        const tokenCreatedEvent = receipt.events?.find((x: any) => x.event === "TokenCreated");

        // Get token contract
        token = await ethers.getContractAt("BuzzToken", tokenCreatedEvent?.args?.token);
    });
    describe("constructor", () => {
        it("should set the factory address", async () => {
            expect(await vault.factory()).to.be.equal(factory.address);
        });
    });
    describe("registerToken", () => {
        beforeEach(async () => {});
        it("should register token transferring totalSupply", async () => {
            const tokenInfo = await vault.tokenInfo(token.address);
            expect(tokenInfo.tokenBalance).to.be.equal(await token.totalSupply());
            //expect(tokenInfo.beraBalance).to.be.equal(0);
            expect(tokenInfo.bexListed).to.be.equal(false);

            expect(tokenInfo.tokenBalance).to.be.equal(await token.balanceOf(vault.address));
        });
        it("should revert if caller is not factory", async () => {
            await expect(vault.connect(user1Signer).registerToken(factory.address, ethers.utils.parseEther("100"))).to.be.revertedWithCustomError(
                vault,
                "BuzzVault_Unauthorized"
            );
        });
    });
    describe("buy", () => {
        beforeEach(async () => {});
        it("should handle multiple buys in succession", async () => {
            const initialVaultTokenBalance = await token.balanceOf(vault.address);
            const initialUser1Balance = await ethers.provider.getBalance(user1Signer.address);
            const initialUser2Balance = await ethers.provider.getBalance(user2Signer.address);

            // Buy 1: user1 buys a small amount of tokens
            await vault
                .connect(user1Signer)
                .buy(token.address, ethers.utils.parseEther("0.0000000001"), ethers.constants.AddressZero, {value: ethers.utils.parseEther("1")});
            const vaultTokenBalanceAfterFirstBuy = await token.balanceOf(vault.address);
            const user1BalanceAfterFirstBuy = await ethers.provider.getBalance(user1Signer.address);
            const tokenInfoAfterFirstBuy = await vault.tokenInfo(token.address);

            console.log("Token balance after first buy:", vaultTokenBalanceAfterFirstBuy.toString());
            console.log("User1 BERA balance after first buy:", user1BalanceAfterFirstBuy.toString());
            console.log("Vault token info after first buy:", tokenInfoAfterFirstBuy);

            expect(vaultTokenBalanceAfterFirstBuy).to.be.below(initialVaultTokenBalance);

            // Buy 2: user2 buys using same BERA amount
            await vault
                .connect(user2Signer)
                .buy(token.address, ethers.utils.parseEther("0.0000000001"), ethers.constants.AddressZero, {value: ethers.utils.parseEther("1")});
            const vaultTokenBalanceAfterSecondBuy = await token.balanceOf(vault.address);
            const user2BalanceAfterSecondBuy = await ethers.provider.getBalance(user2Signer.address);
            const tokenInfoAfterSecondBuy = await vault.tokenInfo(token.address);

            console.log("Token balance after second buy:", vaultTokenBalanceAfterSecondBuy.toString());
            console.log("User2 BERA balance after second buy:", user2BalanceAfterSecondBuy.toString());
            console.log("Vault token info after second buy:", tokenInfoAfterSecondBuy);

            expect(vaultTokenBalanceAfterSecondBuy).to.be.below(vaultTokenBalanceAfterFirstBuy);

            // Assertions on balances, vault state, etc.
            expect(tokenInfoAfterSecondBuy.tokenBalance).to.be.below(tokenInfoAfterFirstBuy.tokenBalance);
            expect(tokenInfoAfterSecondBuy.beraBalance).to.be.above(tokenInfoAfterFirstBuy.beraBalance);
        });
    });
});
