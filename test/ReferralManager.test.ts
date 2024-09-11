import {expect} from "chai";
import {ethers} from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import * as helpers from "@nomicfoundation/hardhat-network-helpers";

import {Contract} from "ethers";

describe("BuzzVault Tests", () => {
    const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
    let feeRecipient: string;

    let ownerSigner: SignerWithAddress;
    let user1Signer: SignerWithAddress;
    let user2Signer: SignerWithAddress;
    let user3Signer: SignerWithAddress;

    let factory: Contract;
    let vault: Contract;
    let token: Contract;
    let referralManager: Contract;
    let eventTracker: Contract;
    let expVault: Contract;
    let tx: any;

    const directRefFeeBps = 1500; // 15% of protocol fee
    const indirectRefFeeBps = 100; // fixed 1%
    const payoutThreshold = 0;
    let validUntil: number;

    beforeEach(async () => {
        validUntil = (await helpers.time.latest()) + ONE_YEAR_IN_SECS;

        [ownerSigner, user1Signer, user2Signer, user3Signer] = await ethers.getSigners();
        feeRecipient = ownerSigner.address;

        // Deploy ReferralManager
        const ReferralManager = await ethers.getContractFactory("ReferralManager");
        referralManager = await ReferralManager.connect(ownerSigner).deploy(directRefFeeBps, indirectRefFeeBps, validUntil, payoutThreshold);

        // Deploy EventTracker
        const EventTracker = await ethers.getContractFactory("BuzzEventTracker");
        eventTracker = await EventTracker.connect(ownerSigner).deploy([]);

        // Deploy factory
        const Factory = await ethers.getContractFactory("BuzzTokenFactory");
        factory = await Factory.connect(ownerSigner).deploy(eventTracker.address);

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
        const tx = await factory.createToken("TEST", "TEST", "Test token is the best", "0x0", vault.address);
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
            await expect(
                vault.connect(user1Signer).buy(token.address, ethers.utils.parseEther("0.001"), user1Signer.address, {
                    value: ethers.utils.parseEther("0.01"),
                })
            ).to.be.revertedWithCustomError(referralManager, "ReferralManager_InvalidParams");
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
    describe("getReferreralBpsFor", () => {
        beforeEach(async () => {
            tx = await vault.connect(ownerSigner).buy(token.address, ethers.utils.parseEther("0.001"), user1Signer.address, {
                value: ethers.utils.parseEther("0.01"),
            });
        });
        it("should return the directFee", async () => {
            expect(await referralManager.getReferreralBpsFor(ownerSigner.address)).to.be.equal(directRefFeeBps);
        });
        it("should return 0 if past the validUntil date", async () => {
            await helpers.time.increase(ONE_YEAR_IN_SECS);
            expect(await referralManager.getReferreralBpsFor(ownerSigner.address)).to.be.equal(0);
        });
        it("should return 0 if the user doesn't have any referrals", async () => {
            expect(await referralManager.getReferreralBpsFor(user1Signer.address)).to.be.equal(0);
        });
        describe("getReferreralBpsFor - indirect referral", () => {
            beforeEach(async () => {
                await vault.connect(user2Signer).buy(token.address, ethers.utils.parseEther("0.001"), ownerSigner.address, {
                    value: ethers.utils.parseEther("0.01"),
                });
            });
            it("should return the directFee + indirect fee", async () => {
                expect(await referralManager.getReferreralBpsFor(user2Signer.address)).to.be.equal(directRefFeeBps + indirectRefFeeBps);
            });
        });
    });
    describe("receiveReferral", () => {
        beforeEach(async () => {
            await referralManager.connect(ownerSigner).setWhitelistedVault(ownerSigner.address, true);
        });
        it("should revert if the caller is not the vault", async () => {
            await expect(
                referralManager.connect(user1Signer).receiveReferral(user2Signer.address, {
                    value: ethers.utils.parseEther("0.01"),
                })
            ).to.be.revertedWithCustomError(referralManager, "ReferralManager_Unauthorised");
        });
        it("should revert if the referrer is not set", async () => {
            await referralManager.connect(ownerSigner).setWhitelistedVault(ownerSigner.address, true);

            await expect(
                referralManager.connect(ownerSigner).receiveReferral(user2Signer.address, {
                    value: ethers.utils.parseEther("0.01"),
                })
            ).to.be.revertedWithCustomError(referralManager, "ReferralManager_InvalidParams");
        });
        it("should allocate the received fee to the user", async () => {
            await referralManager.connect(ownerSigner).setReferral(ownerSigner.address, user1Signer.address);
            await referralManager.connect(ownerSigner).receiveReferral(user1Signer.address, {
                value: ethers.utils.parseEther("0.01"),
            });
            const referrerInfo = await referralManager.referrerInfo(ownerSigner.address);
            expect(referrerInfo[0]).to.be.equal(ethers.utils.parseEther("0.01"));
        });
        it("should allocate the received fee to the direct and indirect referral", async () => {
            await referralManager.connect(ownerSigner).setReferral(ownerSigner.address, user1Signer.address);
            await referralManager.connect(ownerSigner).setReferral(user1Signer.address, user2Signer.address);
            await referralManager.connect(ownerSigner).receiveReferral(user2Signer.address, {
                value: ethers.utils.parseEther("0.01"),
            });
            const referrerInfo = await referralManager.referrerInfo(user1Signer.address);
            expect(referrerInfo[0]).to.be.equal(ethers.utils.parseEther("0.0099"));

            const indirectReferrerInfo = await referralManager.referrerInfo(ownerSigner.address);
            expect(indirectReferrerInfo[0]).to.be.equal(ethers.utils.parseEther("0.0001"));
        });
        it("should emit a ReferralReceived event for the direct referral", async () => {
            await referralManager.connect(ownerSigner).setReferral(ownerSigner.address, user1Signer.address);
            await expect(
                referralManager.connect(ownerSigner).receiveReferral(user1Signer.address, {
                    value: ethers.utils.parseEther("0.01"),
                })
            )
                .to.emit(referralManager, "ReferralRewardReceived")
                .withArgs(ownerSigner.address, ethers.utils.parseEther("0.01"));
        });
    });
    describe("claimReferralReward", () => {
        beforeEach(async () => {
            await referralManager.connect(ownerSigner).setWhitelistedVault(ownerSigner.address, true);
            await referralManager.connect(ownerSigner).setReferral(ownerSigner.address, user1Signer.address);
        });
        it("should revert if reward is below threshold ", async () => {
            await referralManager.connect(ownerSigner).receiveReferral(user1Signer.address, {
                value: ethers.utils.parseEther("0.01"),
            });
            await referralManager.connect(ownerSigner).setPayoutThreshold(ethers.utils.parseEther("0.02"));

            await expect(referralManager.connect(user2Signer).claimReferralReward()).to.be.revertedWithCustomError(
                referralManager,
                "ReferralManager_PayoutBelowThreshold"
            );
        });
        it("should revert if reward is zero", async () => {
            await expect(referralManager.connect(user2Signer).claimReferralReward()).to.be.revertedWithCustomError(
                referralManager,
                "ReferralManager_PayoutBelowThreshold"
            );
        });
        it("should payout any reward", async () => {
            await referralManager.connect(ownerSigner).receiveReferral(user1Signer.address, {
                value: ethers.utils.parseEther("0.01"),
            });
            // store user ether balance
            const userBalanceBefore = await ethers.provider.getBalance(ownerSigner.address);
            const tx = await referralManager.connect(ownerSigner).claimReferralReward();

            // check event
            expect(tx).to.emit(referralManager, "ReferralPaidOut").withArgs(ownerSigner.address, ethers.utils.parseEther("0.01"));
            // check user ether balance
            expect(await ethers.provider.getBalance(ownerSigner.address)).to.be.gt(userBalanceBefore);
        });
        it("should update the accounting", async () => {
            await referralManager.connect(ownerSigner).receiveReferral(user1Signer.address, {
                value: ethers.utils.parseEther("0.01"),
            });
            await referralManager.connect(ownerSigner).claimReferralReward();

            const referrerInfo = await referralManager.referrerInfo(ownerSigner.address);
            expect(referrerInfo[0]).to.be.equal(0);
            expect(referrerInfo[1]).to.be.equal(ethers.utils.parseEther("0.01"));
        });
    });
    describe("setDirectRefFeeBps", () => {
        it("should revert if caller is not owner", async () => {
            await expect(referralManager.connect(user1Signer).setDirectRefFeeBps(2000)).to.be.revertedWith("Ownable: caller is not the owner");
        });
        it("should update the directRefFeeBps", async () => {
            await referralManager.connect(ownerSigner).setDirectRefFeeBps(2000);
            expect(await referralManager.directRefFeeBps()).to.be.equal(2000);
        });
    });
    describe("setIndirectRefFeeBps", () => {
        it("should revert if caller is not owner", async () => {
            await expect(referralManager.connect(user1Signer).setIndirectRefFeeBps(200)).to.be.revertedWith("Ownable: caller is not the owner");
        });
        it("should update the indirectRefFeeBps", async () => {
            await referralManager.connect(ownerSigner).setIndirectRefFeeBps(200);
            expect(await referralManager.indirectRefFeeBps()).to.be.equal(200);
        });
    });
    describe("setValidUntil", () => {
        it("should revert if caller is not owner", async () => {
            await expect(referralManager.connect(user1Signer).setValidUntil(ONE_YEAR_IN_SECS)).to.be.revertedWith("Ownable: caller is not the owner");
        });
        it("should update the validUntil", async () => {
            const timestamp = await helpers.time.latest();
            await referralManager.connect(ownerSigner).setValidUntil(timestamp + ONE_YEAR_IN_SECS);
            expect(await referralManager.validUntil()).to.be.equal(timestamp + ONE_YEAR_IN_SECS);
        });
    });
    describe("setPayoutThreshold", () => {
        it("should revert if caller is not owner", async () => {
            await expect(referralManager.connect(user1Signer).setPayoutThreshold(ethers.utils.parseEther("0.01"))).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );
        });
        it("should update the payoutThreshold", async () => {
            await referralManager.connect(ownerSigner).setPayoutThreshold(ethers.utils.parseEther("1"));
            expect(await referralManager.payoutThreshold()).to.be.equal(ethers.utils.parseEther("1"));
        });
    });
    describe("setWhitelistedVault", () => {
        it("should revert if caller is not owner", async () => {
            await expect(referralManager.connect(user1Signer).setWhitelistedVault(ownerSigner.address, true)).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );
        });
        it("should update the whitelisted vault", async () => {
            await referralManager.connect(ownerSigner).setWhitelistedVault(ownerSigner.address, true);
            expect(await referralManager.whitelistedVaults(ownerSigner.address)).to.be.equal(true);
        });
    });
});
