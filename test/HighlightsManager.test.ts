import {expect} from "chai";
import {ethers} from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {Contract, BigNumber} from "ethers";
import {time} from "@nomicfoundation/hardhat-network-helpers";

describe("HighlightsManager Tests", () => {
    let ownerSigner: SignerWithAddress;
    let treasury: SignerWithAddress;

    let highlightsManager: Contract;
    let token: Contract;

    let duration: number;
    let tx: any;

    const hardcap = 3600; // 1 hour
    const baseFeePerSecond = ethers.utils.parseEther("0.0005");

    beforeEach(async () => {
        [ownerSigner, treasury] = await ethers.getSigners();

        // Deploy mock token
        const SimpleERC20 = await ethers.getContractFactory("SimpleERC20");
        token = await SimpleERC20.connect(ownerSigner).deploy();

        // Deploy Highlights Manager
        const HighlightsManager = await ethers.getContractFactory("HighlightsManager");
        highlightsManager = await HighlightsManager.deploy(treasury.address, hardcap, baseFeePerSecond);
    });
    describe("constructor", () => {
        it("should set the treasury", async () => {
            expect(await highlightsManager.treasury()).to.be.equal(treasury.address);
        });
        it("should set the hardcap", async () => {
            expect(await highlightsManager.hardCap()).to.be.equal(hardcap);
        });
        it("should set the baseFeePerSecond", async () => {
            expect(await highlightsManager.baseFeePerSecond()).to.be.equal(baseFeePerSecond);
        });
    });
    describe("quote", () => {
        beforeEach(async () => {});
        it("should revert if the duration is 0", async () => {
            await expect(highlightsManager.quote(0)).to.be.revertedWithCustomError(highlightsManager, "HighlightsManager_ZeroDuration");
        });
        it("should revert if the duration is lower than the minimum duration", async () => {
            const minimumDuration = await highlightsManager.MIN_DURATION();
            await expect(highlightsManager.quote(minimumDuration.sub(1))).to.be.revertedWithCustomError(
                highlightsManager,
                "HighlightsManager_DurationBelowMinimum"
            );
        });
        it("should revert if the duration is lower than the minimum duration", async () => {
            const hardCap = await highlightsManager.hardCap();
            await expect(highlightsManager.quote(hardCap.add(1))).to.be.revertedWithCustomError(
                highlightsManager,
                "HighlightsManager_DurationExceedsHardCap"
            );
        });
        it("should calculate the fee is the duration is below the exponential threshold", async () => {
            duration = 120; // 2 minutes
            const quote = await highlightsManager.quote(duration);

            expect(quote).to.be.equal(baseFeePerSecond.mul(duration));
        });
        it("should calculate the fee linearly if the duration is the exponential threshold", async () => {
            duration = await highlightsManager.EXP_THRESHOLD();
            const quote = await highlightsManager.quote(duration);

            expect(quote).to.be.equal(baseFeePerSecond.mul(duration));
        });
        it("should calculate the fee exponentially if the duration is above the exponential threshold", async () => {
            const expThreshold = await highlightsManager.EXP_THRESHOLD();
            duration = expThreshold.add(120);

            const quote = await highlightsManager.quote(duration);
            const linearFee = baseFeePerSecond.mul(expThreshold);
            console.log("quote: ", quote.toString());
        });
    });
    describe("highlightToken", () => {
        beforeEach(async () => {
            duration = 120; // 2 minutes
        });
        it("should revert if the msg.value is not enough", async () => {
            const quotedFee = await highlightsManager.quote(duration);

            await expect(highlightsManager.highlightToken(token.address, duration, {value: quotedFee.sub(1)})).to.be.revertedWithCustomError(
                highlightsManager,
                "HighlightsManager_InsufficientFee"
            );
        });
        it("should collect and redirect the fee to the treasury", async () => {
            const quotedFee = await highlightsManager.quote(duration);

            const balanceBefore = await ethers.provider.getBalance(treasury.address);
            await highlightsManager.highlightToken(token.address, duration, {value: quotedFee});
            const balanceAfter = await ethers.provider.getBalance(treasury.address);
            expect(balanceAfter.sub(balanceBefore)).to.be.equal(quotedFee);
        });
        it("should emit a TokenHighlighted event", async () => {
            const quotedFee = await highlightsManager.quote(duration);
            const timestamp = (await time.latest()) + 1; // get timestamp of the next block where the tx would be minted

            await expect(highlightsManager.highlightToken(token.address, duration, {value: quotedFee}))
                .to.emit(highlightsManager, "TokenHighlighted")
                .withArgs(token.address, ownerSigner.address, timestamp, duration, timestamp + duration);
        });
        describe("when there is no other highlight", () => {
            beforeEach(async () => {
                await highlightsManager.highlightToken(token.address, duration, {value: await highlightsManager.quote(duration)});
            });
            it("should set the bookedUntil timestamp to the end of the duration", async () => {
                expect(await highlightsManager.bookedUntil()).to.be.equal((await time.latest()) + duration);
            });
        });
        describe("when there is a previous highlight that hasn't expired", () => {
            beforeEach(async () => {
                await highlightsManager.highlightToken(token.address, duration, {value: await highlightsManager.quote(duration)});
            });
            it("should set the bookedUntil timestamp to the end of the second duration", async () => {
                const currentTimestamp = await time.latest();
                await highlightsManager.highlightToken(token.address, duration, {value: await highlightsManager.quote(duration)});
                expect(await highlightsManager.bookedUntil()).to.be.equal(currentTimestamp + duration * 2);
            });
            it("should set startAt at the end of the last highlight", async () => {
                const previousBookedUntil = await highlightsManager.bookedUntil();
                const tx = await highlightsManager.highlightToken(token.address, duration, {value: await highlightsManager.quote(duration)});
                const receipt = await tx.wait();
                const tokenHighlightedEvent = receipt.events?.find((x: any) => x.event === "TokenHighlighted");

                // Get token contract
                const startAt = tokenHighlightedEvent?.args?.startAt;
                expect(startAt).to.be.equal(previousBookedUntil.add(1));
            });
        });
        describe("when there is a previous highlight that has expired", () => {
            beforeEach(async () => {
                await highlightsManager.highlightToken(token.address, duration, {value: await highlightsManager.quote(duration)});
                await time.increase(duration + 1);
            });
            it("should set the bookedUntil timestamp to the end of the second duration", async () => {
                await highlightsManager.highlightToken(token.address, duration, {value: await highlightsManager.quote(duration)});
                const currentTimestamp = await time.latest();
                expect(await highlightsManager.bookedUntil()).to.be.equal(currentTimestamp + duration);
            });
            it("should set startAt at the current block", async () => {
                const tx = await highlightsManager.highlightToken(token.address, duration, {value: await highlightsManager.quote(duration)});
                const currentTimestamp = await time.latest();

                const receipt = await tx.wait();
                const tokenHighlightedEvent = receipt.events?.find((x: any) => x.event === "TokenHighlighted");

                // Get token contract
                const startAt = tokenHighlightedEvent?.args?.startAt;
                expect(startAt).to.be.equal(currentTimestamp);
            });
        });
    });
    describe("setTreasury", () => {
        beforeEach(async () => {});
        it("should set the treasury", async () => {
            await highlightsManager.setTreasury(ownerSigner.address);
            expect(await highlightsManager.treasury()).to.be.equal(ownerSigner.address);
        });
        it("should emit a TreasurySet event", async () => {
            await expect(highlightsManager.setTreasury(ownerSigner.address)).to.emit(highlightsManager, "TreasurySet").withArgs(ownerSigner.address);
        });
        it("should revert if the treasury is the zero address", async () => {
            await expect(highlightsManager.setTreasury(ethers.constants.AddressZero)).to.be.revertedWithCustomError(
                highlightsManager,
                "HighlightsManager_TreasuryZeroAddress"
            );
        });
        it("should revert if the caller is not the owner", async () => {
            await expect(highlightsManager.connect(treasury).setTreasury(ownerSigner.address)).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });
    describe("setHardCap", () => {
        beforeEach(async () => {});
        it("should set the hard cap", async () => {
            await highlightsManager.setHardCap(1000);
            expect(await highlightsManager.hardCap()).to.be.equal(1000);
        });
        it("should revert if the hard cap is lower than the minimum duration", async () => {
            const minimumDuration = await highlightsManager.MIN_DURATION();
            await expect(highlightsManager.setHardCap(minimumDuration.sub(1))).to.be.revertedWithCustomError(
                highlightsManager,
                "HighlightsManager_HardCapBelowMinimumDuration"
            );
        });
        it("should emit a HardCapSet event", async () => {
            await expect(highlightsManager.setHardCap(1000)).to.emit(highlightsManager, "HardCapSet").withArgs(1000);
        });
        it("should revert if the caller is not the owner", async () => {
            await expect(highlightsManager.connect(treasury).setHardCap(1000)).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });
    describe("setBaseFee", () => {
        beforeEach(async () => {});
        it("should set the fee", async () => {
            await highlightsManager.setBaseFee(ethers.utils.parseEther("0.01"));
            expect(await highlightsManager.baseFeePerSecond()).to.be.equal(ethers.utils.parseEther("0.01"));
        });
        it("should emit a BaseFeeSet event", async () => {
            await expect(highlightsManager.setBaseFee(ethers.utils.parseEther("0.01")))
                .to.emit(highlightsManager, "BaseFeeSet")
                .withArgs(ethers.utils.parseEther("0.01"));
        });
        it("should revert if the caller is not the owner", async () => {
            await expect(highlightsManager.connect(treasury).setBaseFee(ethers.utils.parseEther("0.01"))).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );
        });
    });
});
