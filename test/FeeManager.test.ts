import {expect} from "chai";
import {ethers} from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import * as helpers from "@nomicfoundation/hardhat-network-helpers";

import {Contract, BigNumber} from "ethers";
import {formatBytes32String} from "ethers/lib/utils";

describe("FeeManager Tests", () => {
    let ownerSigner: SignerWithAddress;
    let treasury: SignerWithAddress;

    let feeManager: Contract;
    let token: Contract;
    let tx: any;

    beforeEach(async () => {
        [ownerSigner, treasury] = await ethers.getSigners();

        // Deploy mock token
        const SimpleERC20 = await ethers.getContractFactory("SimpleERC20");
        token = await SimpleERC20.connect(ownerSigner).deploy();

        // Deploy Fee Manager
        const FeeManager = await ethers.getContractFactory("FeeManager");
        feeManager = await FeeManager.deploy(treasury.address, 100, ethers.utils.parseEther("0.02"), 200);
    });
    describe("constructor", () => {
        it("should set the treasury", async () => {
            expect(await feeManager.treasury()).to.be.equal(treasury.address);
        });
        it("should set the tradingFeeBps", async () => {
            expect(await feeManager.tradingFeeBps()).to.be.equal(100);
        });
        it("should set the listingFee", async () => {
            expect(await feeManager.listingFee()).to.be.equal(ethers.utils.parseEther("0.02"));
        });
        it("should set the migrationFeeBps", async () => {
            expect(await feeManager.migrationFeeBps()).to.be.equal(200);
        });
    });
    describe("quoteTradingFee", () => {
        beforeEach(async () => {});
        it("should return the fee", async () => {
            const amount = ethers.utils.parseEther("100");
            const feeAmount = BigNumber.from(amount.mul(100).div(10000));
            const quote = await feeManager.quoteTradingFee(amount);

            expect(quote).to.be.equal(feeAmount);
        });
        it("should return zero if no fee is set", async () => {
            // Set fee to 0
            await feeManager.setTradingFeeBps(0);
            const quote = await feeManager.quoteTradingFee(ethers.utils.parseEther("100"));

            expect(quote).to.be.equal(0);
        });
    });
    describe("quoteMigrationFee", () => {
        beforeEach(async () => {});
        it("should return the fee", async () => {
            const amount = ethers.utils.parseEther("100");
            const feeAmount = BigNumber.from(amount.mul(200).div(10000));
            const quote = await feeManager.quoteMigrationFee(amount);

            expect(quote).to.be.equal(feeAmount);
        });
        it("should return zero if no fee is set", async () => {
            // Set fee to 0
            await feeManager.setMigrationFeeBps(0);
            const quote = await feeManager.quoteMigrationFee(ethers.utils.parseEther("100"));

            expect(quote).to.be.equal(0);
        });
    });
    describe("collectTradingFee", () => {
        beforeEach(async () => {});
        it("should collect and redirect the fee to the treasury", async () => {
            const amount = ethers.utils.parseEther("100");
            const quote = await feeManager.quoteTradingFee(amount);

            const balanceBefore = await token.balanceOf(treasury.address);
            await token.approve(feeManager.address, quote);
            await feeManager.collectTradingFee(token.address, quote);
            const balanceAfter = await token.balanceOf(treasury.address);
            expect(balanceAfter.sub(balanceBefore)).to.be.equal(quote);
        });
        it("should emit a FeeReceived event", async () => {
            const amount = ethers.utils.parseEther("100");
            const quote = await feeManager.quoteTradingFee(amount);

            await token.approve(feeManager.address, quote);
            await expect(feeManager.collectTradingFee(token.address, quote)).to.emit(feeManager, "FeeReceived").withArgs(token.address, quote);
        });
        it("should revert if the fee is not approved", async () => {
            const amount = ethers.utils.parseEther("100");
            await expect(feeManager.collectTradingFee(token.address, amount)).to.be.revertedWith("ERC20: insufficient allowance");
        });
    });
    describe("collectListingFee", () => {
        beforeEach(async () => {});
        it("should collect and redirect the fee to the treasury", async () => {
            const fee = await feeManager.listingFee();

            const balanceBefore = await ethers.provider.getBalance(treasury.address);
            await feeManager.collectListingFee({value: fee});
            const balanceAfter = await ethers.provider.getBalance(treasury.address);
            expect(balanceAfter.sub(balanceBefore)).to.be.equal(fee);
        });
        it("should emit a NativeFeeReceived event", async () => {
            const fee = await feeManager.listingFee();

            await token.approve(feeManager.address, fee);
            await expect(feeManager.collectListingFee({value: fee}))
                .to.emit(feeManager, "NativeFeeReceived")
                .withArgs(fee);
        });
        it("should not transfer tokens if listingFee is zero", async () => {
            // Set fee to 0
            await feeManager.setListingFee(0);

            const balanceBefore = await token.balanceOf(treasury.address);
            await feeManager.collectListingFee();
            const balanceAfter = await token.balanceOf(treasury.address);
            expect(balanceAfter).to.be.equal(balanceBefore);
        });
        it("should revert if the fee is not sent", async () => {
            await expect(feeManager.collectListingFee()).to.be.revertedWithCustomError(feeManager, "FeeManager_InsufficientFee");
        });
    });
    describe("collectMigrationFee", () => {
        beforeEach(async () => {});
        it("should collect and redirect the fee to the treasury", async () => {
            const amount = ethers.utils.parseEther("100");
            const quote = await feeManager.quoteMigrationFee(amount);

            const balanceBefore = await token.balanceOf(treasury.address);
            await token.approve(feeManager.address, quote);
            await feeManager.collectMigrationFee(token.address, amount);
            const balanceAfter = await token.balanceOf(treasury.address);
            expect(balanceAfter.sub(balanceBefore)).to.be.equal(quote);
        });
        it("should emit a FeeReceived event", async () => {
            const amount = ethers.utils.parseEther("100");
            const quote = await feeManager.quoteMigrationFee(amount);

            await token.approve(feeManager.address, quote);
            await expect(feeManager.collectMigrationFee(token.address, amount)).to.emit(feeManager, "FeeReceived").withArgs(token.address, quote);
        });
        it("should not transfer tokens if quote is zero", async () => {
            // Set fee to 0
            await feeManager.setMigrationFeeBps(0);
            const amount = ethers.utils.parseEther("100");

            const balanceBefore = await token.balanceOf(treasury.address);
            await token.approve(feeManager.address, amount);
            await feeManager.collectMigrationFee(token.address, amount);
            const balanceAfter = await token.balanceOf(treasury.address);
            expect(balanceAfter).to.be.equal(balanceBefore);
        });
        it("should revert if the fee is not approved", async () => {
            const amount = ethers.utils.parseEther("100");
            await expect(feeManager.collectMigrationFee(token.address, amount)).to.be.revertedWith("ERC20: insufficient allowance");
        });
    });
    describe("setTradingFeeBps", () => {
        beforeEach(async () => {});
        it("should set the fee", async () => {
            await feeManager.setTradingFeeBps(500);
            expect(await feeManager.tradingFeeBps()).to.be.equal(500);
        });
        it("should emit a TradingFeeSet event", async () => {
            await expect(feeManager.setTradingFeeBps(500)).to.emit(feeManager, "TradingFeeSet").withArgs(500);
        });
        it("should revert if the fee is greater than FEE_DIVISOR", async () => {
            const FEE_DIVISOR = await feeManager.FEE_DIVISOR();
            await expect(feeManager.setTradingFeeBps(FEE_DIVISOR.add(1))).to.be.revertedWithCustomError(
                feeManager,
                "FeeManager_AmountAboveFeeDivisor"
            );
        });
        it("should revert if the caller is not the owner", async () => {
            await expect(feeManager.connect(treasury).setTradingFeeBps(100)).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });
    describe("setListingFee", () => {
        beforeEach(async () => {});
        it("should set the fee", async () => {
            await feeManager.setListingFee(ethers.utils.parseEther("0.01"));
            expect(await feeManager.listingFee()).to.be.equal(ethers.utils.parseEther("0.01"));
        });
        it("should emit a ListingFeeSet event", async () => {
            await expect(feeManager.setListingFee(ethers.utils.parseEther("0.01")))
                .to.emit(feeManager, "ListingFeeSet")
                .withArgs(ethers.utils.parseEther("0.01"));
        });
        it("should revert if the caller is not the owner", async () => {
            await expect(feeManager.connect(treasury).setListingFee(ethers.utils.parseEther("0.01"))).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );
        });
    });
    describe("setMigrationFeeBps", () => {
        beforeEach(async () => {});
        it("should set the fee", async () => {
            await feeManager.setMigrationFeeBps(500);
            expect(await feeManager.migrationFeeBps()).to.be.equal(500);
        });
        it("should emit a MigrationFeeSet event", async () => {
            await expect(feeManager.setMigrationFeeBps(500)).to.emit(feeManager, "MigrationFeeSet").withArgs(500);
        });
        it("should revert if the fee is greater than FEE_DIVISOR", async () => {
            const FEE_DIVISOR = await feeManager.FEE_DIVISOR();
            await expect(feeManager.setMigrationFeeBps(FEE_DIVISOR.add(1))).to.be.revertedWithCustomError(
                feeManager,
                "FeeManager_AmountAboveFeeDivisor"
            );
        });
        it("should revert if the caller is not the owner", async () => {
            await expect(feeManager.connect(treasury).setMigrationFeeBps(100)).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });
    describe("setTreasury", () => {
        beforeEach(async () => {});
        it("should set the treasury", async () => {
            await feeManager.setTreasury(ownerSigner.address);
            expect(await feeManager.treasury()).to.be.equal(ownerSigner.address);
        });
        it("should emit a TreasurySet event", async () => {
            await expect(feeManager.setTreasury(ownerSigner.address)).to.emit(feeManager, "TreasurySet").withArgs(ownerSigner.address);
        });
        it("should revert if the treasury is the zero address", async () => {
            await expect(feeManager.setTreasury(ethers.constants.AddressZero)).to.be.revertedWithCustomError(
                feeManager,
                "FeeManager_TreasuryZeroAddress"
            );
        });
        it("should revert if the caller is not the owner", async () => {
            await expect(feeManager.connect(treasury).setTreasury(ownerSigner.address)).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });
});
