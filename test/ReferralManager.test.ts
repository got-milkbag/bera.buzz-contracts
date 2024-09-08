import {expect} from "chai";
import {ethers} from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import * as helpers from "@nomicfoundation/hardhat-network-helpers";

import {Contract} from "ethers";

describe("BuzzVault Tests", () => {
    const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;

    let ownerSigner: SignerWithAddress;
    let user1Signer: SignerWithAddress;
    let user2Signer: SignerWithAddress;
    let user3Signer: SignerWithAddress;

    let factory: Contract;
    let vault: Contract;
    let token: Contract;
    let referralManager: Contract;
    let tx: any;

    const directRefFeeBps = 1500;
    const indirectRefFeeBps = 100;
    const payoutThreshold = 0;
    let validUntil: number;

    beforeEach(async () => {
        validUntil = (await helpers.time.latest()) + ONE_YEAR_IN_SECS;

        [ownerSigner, user1Signer, user2Signer, user3Signer] = await ethers.getSigners();

        // Deploy ReferralManager
        const ReferralManager = await ethers.getContractFactory("ReferralManager");
        referralManager = await ReferralManager.connect(ownerSigner).deploy(directRefFeeBps, indirectRefFeeBps, validUntil, payoutThreshold);

        // Deploy factory
        const Factory = await ethers.getContractFactory("BuzzTokenFactory");
        factory = await Factory.connect(ownerSigner).deploy();

        // Deploy Vault
        const Vault = await ethers.getContractFactory("BuzzVaultLinear");
        vault = await Vault.connect(ownerSigner).deploy(factory.address, referralManager.address);

        // Admin: Set Vault as the factory's vault & enable token creation
        await factory.connect(ownerSigner).setVault(vault.address, true);
        await factory.connect(ownerSigner).setAllowTokenCreation(true);

        // Admin: Set Vault in the ReferralManager
        await referralManager.connect(ownerSigner).setWhitelistedVault(vault.address, true);

        // Create a token
        const tx = await factory.createToken("TEST", "TEST", vault.address);
        const receipt = await tx.wait();
        const tokenCreatedEvent = receipt.events?.find((x: any) => x.event === "TokenCreated");

        // Get token contract
        token = await ethers.getContractAt("BuzzToken", tokenCreatedEvent?.args?.token);
    });
    describe("constructor", () => {
        it("should set the directRefFeeBps", async () => {
            expect(await referralManager.directRefFeeBps()).to.be.equal(directRefFeeBps);
        });
        it("should set the indirectRefFeeBps", async () => {
            expect(await referralManager.indirectRefFeeBps()).to.be.equal(indirectRefFeeBps);
        });
        it("should set the validUntil", async () => {
            expect(await referralManager.validUntil()).to.be.equal(validUntil);
        });
        it("should set the payoutThreshold", async () => {
            expect(await referralManager.payoutThreshold()).to.be.equal(payoutThreshold);
        });
    });
    describe("setReferral", () => {
        beforeEach(async () => {
            tx = await vault.connect(ownerSigner).buy(token.address, ethers.utils.parseEther("0.001"), user1Signer.address, {
                value: ethers.utils.parseEther("0.01"),
            });
        });
        it("should set referredBy for ownerSigner to user1", async () => {
            const referredBy = await referralManager.referredBy(ownerSigner.address);
            expect(referredBy).to.be.equal(user1Signer.address);
        });
        it("should keep indirectReferral to zero", async () => {
            const indirectReferral = await referralManager.indirectReferral(user1Signer.address);
            expect(indirectReferral).to.be.equal(ethers.constants.AddressZero);
        });
        it("should revert if caller is not vault", async () => {
            await expect(referralManager.connect(user1Signer).setReferral(ownerSigner.address, user1Signer.address)).to.be.revertedWithCustomError(
                referralManager,
                "ReferralManager_Unauthorised"
            );
        });
        it("should not update the referral if one is already set", async () => {
            expect(await referralManager.referredBy(ownerSigner.address)).to.be.equal(user1Signer.address);
            await vault.connect(ownerSigner).buy(token.address, ethers.utils.parseEther("0.001"), user2Signer.address, {
                value: ethers.utils.parseEther("0.01"),
            });
            expect(await referralManager.referredBy(ownerSigner.address)).to.be.equal(user1Signer.address);
        });
        it("should not set the referral if it's the same as msg.sender", async () => {
            await vault.connect(user1Signer).buy(token.address, ethers.utils.parseEther("0.001"), user1Signer.address, {
                value: ethers.utils.parseEther("0.01"),
            });
            expect(await referralManager.referredBy(user1Signer.address)).to.be.equal(ethers.constants.AddressZero);
        });
        it("should increase the referralCount counter", async () => {
            const referrerInfo = await referralManager.referrerInfo(user1Signer.address);
            expect(referrerInfo[2]).to.be.equal(1);
        });
        it("should emit a ReferralSet event", async () => {
            await expect(tx).to.emit(referralManager, "ReferralSet");
        });
        describe("setReferral - indirect referral", () => {
            beforeEach(async () => {
                tx = await vault.connect(user2Signer).buy(token.address, ethers.utils.parseEther("0.001"), ownerSigner.address, {
                    value: ethers.utils.parseEther("0.01"),
                });
            });
            it("should set the indirect referral", async () => {
                expect(await referralManager.indirectReferral(user2Signer.address)).to.be.equal(user1Signer.address);
            });
            it("should set the direct referral", async () => {
                expect(await referralManager.referredBy(user2Signer.address)).to.be.equal(ownerSigner.address);
            });
            it("should increase the indirectReferrer counter", async () => {
                const referrerInfo = await referralManager.referrerInfo(user1Signer.address);
                expect(referrerInfo[3]).to.be.equal(1);
            });
            it("should emit an IndirectReferralSet event", async () => {
                await expect(tx).to.emit(referralManager, "IndirectReferralSet");
            });
        });
    });
});
