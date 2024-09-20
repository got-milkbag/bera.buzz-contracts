import {expect} from "chai";
import {ethers} from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import * as helpers from "@nomicfoundation/hardhat-network-helpers";
import {Contract} from "ethers";
import { formatBytes32String } from "ethers/lib/utils";

describe("BuzzVaultExponential Tests", () => {
    const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
    let feeRecipient: string;

    let ownerSigner: SignerWithAddress;
    let user1Signer: SignerWithAddress;
    let user2Signer: SignerWithAddress;
    let factory: Contract;
    let vault: Contract;
    let token: Contract;
    let referralManager: Contract;
    let eventTracker: Contract;
    let expVault: Contract;

    const directRefFeeBps = 1500; // 15% of protocol fee
    const indirectRefFeeBps = 100; // fixed 1%
    const payoutThreshold = 0;
    let validUntil: number;

    beforeEach(async () => {
        validUntil = (await helpers.time.latest()) + ONE_YEAR_IN_SECS;

        [ownerSigner, user1Signer, user2Signer] = await ethers.getSigners();
        feeRecipient = ownerSigner.address;

        // Deploy ReferralManager
        const ReferralManager = await ethers.getContractFactory("ReferralManager");
        referralManager = await ReferralManager.connect(ownerSigner).deploy(directRefFeeBps, indirectRefFeeBps, validUntil, payoutThreshold);

        // Deploy EventTracker
        const EventTracker = await ethers.getContractFactory("BuzzEventTracker");
        eventTracker = await EventTracker.connect(ownerSigner).deploy([]);

        // Deploy factory
        const Factory = await ethers.getContractFactory("BuzzTokenFactory");
        factory = await Factory.connect(ownerSigner).deploy(eventTracker.address, ownerSigner.address);

        // Deploy Linear Vault
        const Vault = await ethers.getContractFactory("BuzzVaultLinear");
        vault = await Vault.connect(ownerSigner).deploy(feeRecipient, factory.address, referralManager.address, eventTracker.address);

        // Deploy Exponential Vault
        const ExpVault = await ethers.getContractFactory("BuzzVaultExponential");
        expVault = await ExpVault.connect(ownerSigner).deploy(feeRecipient, factory.address, referralManager.address, eventTracker.address);

        // Admin: Set Vault in the ReferralManager
        await referralManager.connect(ownerSigner).setWhitelistedVault(vault.address, true);
        await referralManager.connect(ownerSigner).setWhitelistedVault(expVault.address, true);

        // Admin: Set event setter contracts in EventTracker
        await eventTracker.connect(ownerSigner).setEventSetter(vault.address, true);
        await eventTracker.connect(ownerSigner).setEventSetter(expVault.address, true);
        await eventTracker.connect(ownerSigner).setEventSetter(factory.address, true);

        // Admin: Set Vault as the factory's vault & enable token creation
        await factory.connect(ownerSigner).setVault(vault.address, true);
        await factory.connect(ownerSigner).setVault(expVault.address, true);

        await factory.connect(ownerSigner).setAllowTokenCreation(true);
        // Create a token
        const tx = await factory.createToken("TEST", "TEST", "Test token is the best", "0x0", vault.address, formatBytes32String("12345"));
        const receipt = await tx.wait();
        const tokenCreatedEvent = receipt.events?.find((x: any) => x.event === "TokenCreated");

        // Get token contract
        token = await ethers.getContractAt("BuzzToken", tokenCreatedEvent?.args?.token);
    });
    describe("constructor", () => {
        it("should set the factory address", async () => {
            expect(await vault.factory()).to.be.equal(factory.address);
        });
        it("should set the feeRecipient address", async () => {
            expect(await vault.feeRecipient()).to.be.equal(feeRecipient);
        });
        it("should set the referralManager address", async () => {
            expect(await vault.referralManager()).to.be.equal(referralManager.address);
        });
        it("should set the eventTracker address", async () => {
            expect(await vault.eventTracker()).to.be.equal(eventTracker.address);
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
