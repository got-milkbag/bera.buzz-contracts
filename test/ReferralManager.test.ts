import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import * as helpers from "@nomicfoundation/hardhat-network-helpers";

import { BigNumber, Contract } from "ethers";
import { formatBytes32String } from "ethers/lib/utils";

describe("ReferralManager Tests", () => {
    const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;

    let ownerSigner: SignerWithAddress;
    let user1Signer: SignerWithAddress;
    let user2Signer: SignerWithAddress;
    let treasury: SignerWithAddress;

    let factory: Contract;
    let token: Contract;
    let referralManager: Contract;
    let expVault: Contract;
    let tx: any;
    let bexLpToken: Contract;
    let crocQuery: Contract;
    let bexPriceDecoder: Contract;
    let create3Factory: Contract;
    let bexLiquidityManager: Contract;
    let wBera: Contract;
    let feeManager: Contract;

    const directRefFeeBps = 1500; // 15% of protocol fee
    const indirectRefFeeBps = 100; // fixed 1%
    const listingFee = ethers.utils.parseEther("0.02");
    const payoutThreshold = 0;
    const crocSwapDexAddress = "0xAB827b1Cc3535A9e549EE387A6E9C3F02F481B49";
    let validUntil: number;

    beforeEach(async () => {
        validUntil = (await helpers.time.latest()) + ONE_YEAR_IN_SECS;

        [ownerSigner, user1Signer, user2Signer, treasury] = await ethers.getSigners();

        // Deploy mock create3Factory
        const Create3Factory = await ethers.getContractFactory("CREATE3FactoryMock");
        create3Factory = await Create3Factory.connect(ownerSigner).deploy();

        // Deploy mock BexLpToken
        const BexLpToken = await ethers.getContractFactory("BexLPTokenMock");
        bexLpToken = await BexLpToken.connect(ownerSigner).deploy(36000, ethers.constants.AddressZero, ethers.constants.AddressZero);

        //Deploy mock ICrocQuery
        const ICrocQuery = await ethers.getContractFactory("CrocQueryMock");
        crocQuery = await ICrocQuery.connect(ownerSigner).deploy(ethers.BigNumber.from("83238796252293901415"));

        // Deploy liquidity manager
        const BexLiquidityManager = await ethers.getContractFactory("BexLiquidityManager");
        bexLiquidityManager = await BexLiquidityManager.connect(ownerSigner).deploy(crocSwapDexAddress);
        await bexLiquidityManager.addVaults([ownerSigner.address]);

        //Deploy WBera Mock
        const WBera = await ethers.getContractFactory("WBERA");
        wBera = await WBera.connect(ownerSigner).deploy();

        // Deploy BexPriceDecoder
        const BexPriceDecoder = await ethers.getContractFactory("BexPriceDecoder");
        bexPriceDecoder = await BexPriceDecoder.connect(ownerSigner).deploy(
            crocQuery.address, 
            [wBera.address],
            [bexLpToken.address]
        );

        // Deploy ReferralManager
        const ReferralManager = await ethers.getContractFactory("ReferralManager");
        referralManager = await ReferralManager.connect(ownerSigner).deploy(
            directRefFeeBps,
            indirectRefFeeBps,
            validUntil,
            [wBera.address],
            [payoutThreshold]
        );

        // Deploy FeeManager
        const FeeManager = await ethers.getContractFactory("FeeManager");
        feeManager = await FeeManager.connect(ownerSigner).deploy(treasury.address, 100, listingFee, 500);

        // Deploy factory
        const Factory = await ethers.getContractFactory("BuzzTokenFactory");
        factory = await Factory.connect(ownerSigner).deploy(ownerSigner.address, create3Factory.address, feeManager.address);
        // Deploy Linear Vault
        //const Vault = await ethers.getContractFactory("BuzzVaultLinear");
        //vault = await Vault.connect(ownerSigner).deploy(feeRecipient, factory.address, referralManager.address, eventTracker.address, bexPriceDecoder.address, bexLiquidityManager.address);

        // Deploy Exponential Vault
        const ExpVault = await ethers.getContractFactory("BuzzVaultExponential");
        expVault = await ExpVault.connect(ownerSigner).deploy(
            feeManager.address,
            factory.address,
            referralManager.address,
            bexPriceDecoder.address,
            bexLiquidityManager.address,
            wBera.address
        );

        // Admin: Set Vault in the ReferralManager
        await referralManager.connect(ownerSigner).setWhitelistedVault(expVault.address, true);

        // Admin: Whitelist base token in Factory
        await factory.connect(ownerSigner).setAllowedBaseToken(wBera.address, true);

        // Admin: Set Vault as the factory's vault & enable token creation
        await factory.connect(ownerSigner).setVault(expVault.address, true);
        await factory.connect(ownerSigner).setAllowTokenCreation(true);

        // Create a token
        const tx = await factory.createToken(
            ["TEST", "TST"],
            [wBera.address, expVault.address],
            [ethers.utils.parseEther("2.22"), BigNumber.from("3350000000")],
            0,
            formatBytes32String("12345"),
            ethers.utils.parseEther("69420"),
            {
                value: listingFee,
            }
        );
        const receipt = await tx.wait();
        const tokenCreatedEvent = receipt.events?.find((x: any) => x.event === "TokenCreated");

        // Get token contract
        token = await ethers.getContractAt("BuzzToken", tokenCreatedEvent?.args?.token);

        // Get some WBEra
        await wBera.connect(ownerSigner).deposit({ value: ethers.utils.parseEther("10") });
        await wBera.approve(referralManager.address, ethers.utils.parseEther("1"));
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
            expect(await referralManager.payoutThreshold(wBera.address)).to.be.equal(payoutThreshold);
        });
        describe("constructor - invalid parameters", () => {
            it("should revert if there is an array mismatch", async () => {
                const ReferralManager = await ethers.getContractFactory("ReferralManager");
                await expect(
                    ReferralManager.connect(ownerSigner).deploy(
                        directRefFeeBps,
                        indirectRefFeeBps,
                        validUntil,
                        [wBera.address],
                        [payoutThreshold, payoutThreshold]
                    )
                ).to.be.revertedWithCustomError(referralManager, "ReferralManager_ArrayLengthMismatch");
            });
        });
    });
    describe("setReferral", () => {
        beforeEach(async () => {
            tx = await expVault.connect(ownerSigner).buyNative(token.address, ethers.utils.parseEther("0.001"), user1Signer.address, {
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
            await expVault.connect(ownerSigner).buyNative(token.address, ethers.utils.parseEther("0.001"), user2Signer.address, {
                value: ethers.utils.parseEther("0.01"),
            });
            expect(await referralManager.referredBy(ownerSigner.address)).to.be.equal(user1Signer.address);
        });
        it("should not set the referral if it's the same as msg.sender", async () => {
            await expVault.connect(user1Signer).buyNative(token.address, ethers.utils.parseEther("0.001"), user1Signer.address, {
                value: ethers.utils.parseEther("0.01"),
            });
            expect(await referralManager.referredBy(user1Signer.address)).to.be.equal(ethers.constants.AddressZero);
        });
        it("should emit a ReferralSet event", async () => {
            await expect(tx).to.emit(referralManager, "ReferralSet").withArgs(user1Signer.address, ownerSigner.address);
        });
        describe("setReferral - indirect referral", () => {
            beforeEach(async () => {
                tx = await expVault.connect(user2Signer).buyNative(token.address, ethers.utils.parseEther("0.001"), ownerSigner.address, {
                    value: ethers.utils.parseEther("0.01"),
                });
            });
            it("should set the indirect referral", async () => {
                expect(await referralManager.indirectReferral(user2Signer.address)).to.be.equal(user1Signer.address);
            });
            it("should set the direct referral", async () => {
                expect(await referralManager.referredBy(user2Signer.address)).to.be.equal(ownerSigner.address);
            });
            it("should emit an IndirectReferralSet event", async () => {
                await expect(tx)
                    .to.emit(referralManager, "IndirectReferralSet")
                    .withArgs(user1Signer.address, user2Signer.address, ownerSigner.address);
            });
        });
    });
    describe("getReferralBpsFor", () => {
        beforeEach(async () => {
            tx = await expVault.connect(ownerSigner).buyNative(token.address, ethers.utils.parseEther("0.001"), user1Signer.address, {
                value: ethers.utils.parseEther("0.01"),
            });
        });
        it("should return the directFee", async () => {
            expect(await referralManager.getReferralBpsFor(ownerSigner.address)).to.be.equal(directRefFeeBps);
        });
        it("should return 0 if past the validUntil date", async () => {
            await helpers.time.increase(ONE_YEAR_IN_SECS);
            expect(await referralManager.getReferralBpsFor(ownerSigner.address)).to.be.equal(0);
        });
        it("should return 0 if the user doesn't have any referrals", async () => {
            expect(await referralManager.getReferralBpsFor(user1Signer.address)).to.be.equal(0);
        });
        describe("getReferralBpsFor - indirect referral", () => {
            beforeEach(async () => {
                await expVault.connect(user2Signer).buyNative(token.address, ethers.utils.parseEther("0.001"), ownerSigner.address, {
                    value: ethers.utils.parseEther("0.01"),
                });
            });
            it("should return the directFee + indirect fee", async () => {
                expect(await referralManager.getReferralBpsFor(user2Signer.address)).to.be.equal(directRefFeeBps + indirectRefFeeBps);
            });
        });
    });
    describe("receiveReferral", () => {
        beforeEach(async () => {
            await referralManager.connect(ownerSigner).setWhitelistedVault(ownerSigner.address, true);
        });
        it("should revert if the caller is not the vault", async () => {
            await expect(
                referralManager.connect(user1Signer).receiveReferral(user2Signer.address, wBera.address, ethers.utils.parseEther("0.01"))
            ).to.be.revertedWithCustomError(referralManager, "ReferralManager_Unauthorised");
        });
        it("should revert if the referrer is not set", async () => {
            await referralManager.connect(ownerSigner).setWhitelistedVault(ownerSigner.address, true);

            await expect(
                referralManager.connect(ownerSigner).receiveReferral(user2Signer.address, wBera.address, ethers.utils.parseEther("0.01"))
            ).to.be.revertedWithCustomError(referralManager, "ReferralManager_AddressZero");
        });
        it("should allocate the received fee to the user", async () => {
            await referralManager.connect(ownerSigner).setReferral(ownerSigner.address, user1Signer.address);
            await referralManager.connect(ownerSigner).receiveReferral(user1Signer.address, wBera.address, ethers.utils.parseEther("0.01"));
            const referrerBalance = await referralManager.getReferralRewardFor(ownerSigner.address, wBera.address);
            expect(referrerBalance).to.be.equal(ethers.utils.parseEther("0.01"));
        });
        it("should allocate the received fee to the direct and indirect referral", async () => {
            await referralManager.connect(ownerSigner).setReferral(ownerSigner.address, user1Signer.address);
            await referralManager.connect(ownerSigner).setReferral(user1Signer.address, user2Signer.address);
            await referralManager.connect(ownerSigner).receiveReferral(user2Signer.address, wBera.address, ethers.utils.parseEther("0.01"));
            const referrerBalance = await referralManager.getReferralRewardFor(user1Signer.address, wBera.address);
            expect(referrerBalance).to.be.equal(ethers.utils.parseEther("0.0099"));

            const indirectReferrerInfo = await referralManager.getReferralRewardFor(ownerSigner.address, wBera.address);
            expect(indirectReferrerInfo).to.be.equal(ethers.utils.parseEther("0.0001"));
        });
        it("should emit a ReferralReceived event for the direct referral", async () => {
            await referralManager.connect(ownerSigner).setReferral(ownerSigner.address, user1Signer.address);
            await expect(referralManager.connect(ownerSigner).receiveReferral(user1Signer.address, wBera.address, ethers.utils.parseEther("0.01")))
                .to.emit(referralManager, "ReferralRewardReceived")
                .withArgs(ownerSigner.address, wBera.address, ethers.utils.parseEther("0.01"), true);
        });
        it("should emit a ReferralReceived event for the indirect referral", async () => {
            await referralManager.connect(ownerSigner).setReferral(ownerSigner.address, user1Signer.address);
            await referralManager.connect(ownerSigner).setReferral(user1Signer.address, user2Signer.address);
            await expect(referralManager.connect(ownerSigner).receiveReferral(user2Signer.address, wBera.address, ethers.utils.parseEther("0.01")))
                .to.emit(referralManager, "ReferralRewardReceived")
                .withArgs(ownerSigner.address, wBera.address, ethers.utils.parseEther("0.0001"), false);
        });
    });

    describe("claimReferralReward", () => {
        beforeEach(async () => {
            await referralManager.connect(ownerSigner).setWhitelistedVault(ownerSigner.address, true);
            await referralManager.connect(ownerSigner).setReferral(ownerSigner.address, user1Signer.address);
        });
        it("should revert if reward is below threshold ", async () => {
            await referralManager.connect(ownerSigner).receiveReferral(user1Signer.address, wBera.address, ethers.utils.parseEther("0.01"));
            await referralManager.connect(ownerSigner).setPayoutThreshold([wBera.address], [ethers.utils.parseEther("0.02")]);

            await expect(referralManager.connect(user2Signer).claimReferralReward(wBera.address)).to.be.revertedWithCustomError(
                referralManager,
                "ReferralManager_PayoutBelowThreshold"
            );
        });
        it("should revert if reward is zero", async () => {
            await expect(referralManager.connect(user2Signer).claimReferralReward(wBera.address)).to.be.revertedWithCustomError(
                referralManager,
                "ReferralManager_ZeroPayout"
            );
        });
        it("should payout any reward", async () => {
            const referralAmount = ethers.utils.parseEther("0.01");
            await referralManager.connect(ownerSigner).receiveReferral(user1Signer.address, wBera.address, referralAmount);
            // store user ether balance
            const userBalanceBefore = await wBera.balanceOf(ownerSigner.address);
            const tx = await referralManager.connect(ownerSigner).claimReferralReward(wBera.address);

            // check event
            expect(tx).to.emit(referralManager, "ReferralPaidOut").withArgs(ownerSigner.address, wBera.address, referralAmount);
            // check user ether balance
            expect(await wBera.balanceOf(ownerSigner.address)).to.be.equal(userBalanceBefore.add(referralAmount));
        });
        it("should update the accounting", async () => {
            await referralManager.connect(ownerSigner).receiveReferral(user1Signer.address, wBera.address, ethers.utils.parseEther("0.01"));
            await referralManager.connect(ownerSigner).claimReferralReward(wBera.address);

            expect(await referralManager.getReferralRewardFor(ownerSigner.address, wBera.address)).to.be.equal(0);
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
            await expect(
                referralManager.connect(user1Signer).setPayoutThreshold([wBera.address], [ethers.utils.parseEther("0.01")])
            ).to.be.revertedWith("Ownable: caller is not the owner");
        });
        it("should update the payoutThreshold", async () => {
            await referralManager.connect(ownerSigner).setPayoutThreshold([wBera.address], [ethers.utils.parseEther("1")]);
            expect(await referralManager.payoutThreshold(wBera.address)).to.be.equal(ethers.utils.parseEther("1"));
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
            expect(await referralManager.whitelistedVault(ownerSigner.address)).to.be.equal(true);
        });
    });
    describe("pause", () => {
        beforeEach(async () => {});
        it("should pause the contract", async () => {
            await referralManager.pause();
            expect(await referralManager.paused()).to.be.true;
        });
        it("should emit a Paused event", async () => {
            await expect(referralManager.pause()).to.emit(referralManager, "Paused");
        });
        it("should revert if the caller is not the owner", async () => {
            await expect(referralManager.connect(treasury).pause()).to.be.revertedWith("Ownable: caller is not the owner");
        });
        it("should not allow calling claimReferralReward", async () => {
            await referralManager.pause();

            await referralManager.connect(ownerSigner).setWhitelistedVault(ownerSigner.address, true);
            await referralManager.connect(ownerSigner).setReferral(ownerSigner.address, user1Signer.address);

            const referralAmount = ethers.utils.parseEther("0.01");
            await referralManager.connect(ownerSigner).receiveReferral(user1Signer.address, wBera.address, referralAmount);
            // store user ether balance
            await expect(referralManager.connect(user1Signer).claimReferralReward(wBera.address)).to.be.revertedWith("Pausable: paused");
        });
    });
    describe("unpause", () => {
        beforeEach(async () => {
            await referralManager.pause();
        });
        it("should unpause the contract", async () => {
            await referralManager.unpause();
            expect(await referralManager.paused()).to.be.false;
        });
        it("should emit a Unpaused event", async () => {
            await expect(referralManager.unpause()).to.emit(referralManager, "Unpaused");
        });
        it("should revert if the caller is not the owner", async () => {
            await expect(referralManager.connect(treasury).unpause()).to.be.revertedWith("Ownable: caller is not the owner");
        });
        it("should allow calling claimReferralReward", async () => {
            await referralManager.unpause();

            await referralManager.connect(ownerSigner).setWhitelistedVault(ownerSigner.address, true);
            await referralManager.connect(ownerSigner).setReferral(ownerSigner.address, user1Signer.address);

            const referralAmount = ethers.utils.parseEther("0.01");
            await referralManager.connect(ownerSigner).receiveReferral(user1Signer.address, wBera.address, referralAmount);
            // store user ether balance
            const userBalanceBefore = await wBera.balanceOf(ownerSigner.address);
            const tx = await referralManager.connect(ownerSigner).claimReferralReward(wBera.address);

            // check event
            expect(tx).to.emit(referralManager, "ReferralPaidOut").withArgs(ownerSigner.address, wBera.address, referralAmount);
            // check user ether balance
            expect(await wBera.balanceOf(ownerSigner.address)).to.be.equal(userBalanceBefore.add(referralAmount));
        });
    });
});
