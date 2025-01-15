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
    let suffix: string;

    const hardcap = 3600; // 1 hour
    const baseFeePerSecond = ethers.utils.parseEther("0.0005");
    const coolDownPeriod = 12 * 60 * 60; // 12 hours in seconds

    beforeEach(async () => {
        [ownerSigner, treasury] = await ethers.getSigners();

        // Deploy mock token
        const SimpleERC20 = await ethers.getContractFactory("SimpleERC20");
        token = await SimpleERC20.connect(ownerSigner).deploy();

        // get last 3 characters from contract address and add it as the suffix in HighlightsManager
        suffix = token.address.slice(-3);
        suffix = suffix.toLowerCase();

        // Deploy Highlights Manager
        const HighlightsManager = await ethers.getContractFactory("HighlightsManager");
        highlightsManager = await HighlightsManager.deploy(treasury.address, hardcap, baseFeePerSecond, coolDownPeriod, suffix);
    });
    describe("constructor", () => {
        it("should revert if hardCap is less than MIN_DURATION", async () => {
            const HighlightsManager = await ethers.getContractFactory("HighlightsManager");
            await expect(HighlightsManager.deploy(treasury.address, 59, baseFeePerSecond, coolDownPeriod, suffix)).to.be.revertedWithCustomError(
                highlightsManager,
                "HighlightsManager_HardCapBelowMinimumDuration"
            );
        });
        it("should set the treasury", async () => {
            expect(await highlightsManager.treasury()).to.be.equal(treasury.address);
        });
        it("should set the hardcap", async () => {
            expect(await highlightsManager.hardCap()).to.be.equal(hardcap);
        });
        it("should set the baseFeePerSecond", async () => {
            expect(await highlightsManager.baseFeePerSecond()).to.be.equal(baseFeePerSecond);
        });
        it("should set the coolDownPeriod", async () => {
            expect(await highlightsManager.coolDownPeriod()).to.be.equal(coolDownPeriod);
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
            // console.log("quote: ", quote.toString());
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
        it("should refund the difference if the user overpays", async () => {
            const quotedFee = await highlightsManager.quote(duration);
      
            const balanceBefore = await ethers.provider.getBalance(
              ownerSigner.address
            );
            const tx = await highlightsManager.highlightToken(
              token.address,
              duration,
              { value: quotedFee.add(100) } // Overpay by 100 wei
            );
      
            const txReceipt = await tx.wait();
            const gasUsed = txReceipt.cumulativeGasUsed.mul(
              txReceipt.effectiveGasPrice
            );
      
            expect(await ethers.provider.getBalance(ownerSigner.address)).to.be.equal(
              balanceBefore.sub(quotedFee).sub(gasUsed)
            );
        });
        it("should revert if the token address doesn't contain the right suffix", async () => {
            // Redeploy token contract to get a different suffix
            const SimpleERC20 = await ethers.getContractFactory("SimpleERC20");
            token = await SimpleERC20.connect(ownerSigner).deploy();

            const quotedFee = await highlightsManager.quote(duration);
            await expect(highlightsManager.highlightToken(ownerSigner.address, duration, {value: quotedFee})).to.be.revertedWithCustomError(
                highlightsManager,
                "HighlightsManager_UnrecognisedToken"
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
                .withArgs(token.address, ownerSigner.address, duration, timestamp + duration, quotedFee);
        });
        describe("when there is a previous highlight that hasn't expired", () => {
            beforeEach(async () => {
                await highlightsManager.highlightToken(token.address, duration, {value: await highlightsManager.quote(duration)});
            });
            it("should revert with Slot Occupied", async () => {
                await expect(
                    highlightsManager.highlightToken(token.address, duration, {value: await highlightsManager.quote(duration)})
                ).to.be.revertedWithCustomError(highlightsManager, "HighlightsManager_SlotOccupied");
            });
        });
        describe("when the token is within the cool down period", () => {
            beforeEach(async () => {
                await highlightsManager.highlightToken(token.address, duration, {value: await highlightsManager.quote(duration)});
                await time.increase(duration + 1);
            });
            it("should revert with Token Within CoolDown", async () => {
                await expect(
                    highlightsManager.highlightToken(token.address, duration, {value: await highlightsManager.quote(duration)})
                ).to.be.revertedWithCustomError(highlightsManager, "HighlightsManager_TokenWithinCoolDown");
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
                "HighlightsManager_TreasuryAddressZero"
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
    describe("setCoolDownPeriod", () => {
        beforeEach(async () => {});
        it("should set the cool down period", async () => {
            await highlightsManager.setCoolDownPeriod(1000);
            expect(await highlightsManager.coolDownPeriod()).to.be.equal(1000);
        });
        it("should emit a CoolDownPeriodSet event", async () => {
            await expect(highlightsManager.setCoolDownPeriod(1000)).to.emit(highlightsManager, "CoolDownPeriodSet").withArgs(1000);
        });
        it("should revert if the caller is not the owner", async () => {
            await expect(highlightsManager.connect(treasury).setCoolDownPeriod(1000)).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });
    describe("pause", () => {
        beforeEach(async () => {
            duration = 120; // 2 minutes
        });
        it("should pause the contract", async () => {
            await highlightsManager.pause();
            expect(await highlightsManager.paused()).to.be.true;
        });
        it("should emit a Paused event", async () => {
            await expect(highlightsManager.pause()).to.emit(highlightsManager, "Paused");
        });
        it("should revert if the caller is not the owner", async () => {
            await expect(highlightsManager.connect(treasury).pause()).to.be.revertedWith("Ownable: caller is not the owner");
        });
        it("should not allow calling highlightToken", async () => {
            await highlightsManager.pause();
            const quotedFee = await highlightsManager.quote(duration);
            await expect(highlightsManager.connect(ownerSigner).highlightToken(token.address, duration, {value: quotedFee})).to.be.revertedWith("Pausable: paused");
        });
    });
    describe("unpause", () => {
        beforeEach(async () => {
            await highlightsManager.pause();
        });
        it("should unpause the contract", async () => {
            await highlightsManager.unpause();
            expect(await highlightsManager.paused()).to.be.false;
        });
        it("should emit a Unpaused event", async () => {
            await expect(highlightsManager.unpause()).to.emit(highlightsManager, "Unpaused");
        });
        it("should revert if the caller is not the owner", async () => {
            await expect(highlightsManager.connect(treasury).unpause()).to.be.revertedWith("Ownable: caller is not the owner");
        });
        it("should allow calling highlightToken", async () => {
            await highlightsManager.unpause();
            const quotedFee = await highlightsManager.quote(duration);
            const balanceBefore = await ethers.provider.getBalance(treasury.address);

            await highlightsManager.connect(ownerSigner).highlightToken(token.address, duration, {value: quotedFee});
            
            const balanceAfter = await ethers.provider.getBalance(treasury.address);
            expect(balanceAfter.sub(balanceBefore)).to.be.equal(quotedFee);
        });
    });
});
