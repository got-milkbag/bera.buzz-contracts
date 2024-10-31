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
        feeManager = await FeeManager.deploy(treasury.address, 1000, ethers.utils.parseEther("0.02"), 2000);
    });
    describe("constructor", () => {
        it("should set the treasury", async () => {
            expect(await feeManager.treasury()).to.be.equal(treasury.address);
        });
        it("should set the tradingFeeBps", async () => {
            expect(await feeManager.tradingFeeBps()).to.be.equal(1000);
        });
        it("should set the listingFee", async () => {
            expect(await feeManager.listingFee()).to.be.equal(ethers.utils.parseEther("0.02"));
        });
        it("should set the migrationFeeBps", async () => {
            expect(await feeManager.migrationFeeBps()).to.be.equal(2000);
        });
    });
    describe("quoteTradingFee", () => {
        beforeEach(async () => {
            const FeeManager = await ethers.getContractFactory("FeeManager");
            feeManager = await FeeManager.deploy(treasury.address, 1000, ethers.utils.parseEther("0.02"), 2000);
        });
        it("should return the fee", async () => {
            const amount = ethers.utils.parseEther("100");
            const feeAmount = BigNumber.from(amount.mul(1000).div(100000));
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
        beforeEach(async () => {
            const FeeManager = await ethers.getContractFactory("FeeManager");
            feeManager = await FeeManager.deploy(treasury.address, 1000, ethers.utils.parseEther("0.02"), 2000);
        });
        it("should return the fee", async () => {
            const amount = ethers.utils.parseEther("100");
            const feeAmount = BigNumber.from(amount.mul(2000).div(100000));
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
        beforeEach(async () => {
            const FeeManager = await ethers.getContractFactory("FeeManager");
            feeManager = await FeeManager.deploy(treasury.address, 1000, ethers.utils.parseEther("0.02"), 2000);
        });
        it("should collect and redirect the fee to the treasury", async () => {
            const amount = ethers.utils.parseEther("100");
            const quote = await feeManager.quoteTradingFee(amount);

            const balanceBefore = await token.balanceOf(treasury.address);
            await token.approve(feeManager.address, quote);
            await feeManager.collectTradingFee(token.address, amount);
            const balanceAfter = await token.balanceOf(treasury.address);
            expect(balanceAfter.sub(balanceBefore)).to.be.equal(quote);
        });
        it("should emit a FeeReceived event", async () => {
            const amount = ethers.utils.parseEther("100");
            const quote = await feeManager.quoteTradingFee(amount);

            await token.approve(feeManager.address, quote);
            await expect(feeManager.collectTradingFee(token.address, amount)).to.emit(feeManager, "FeeReceived").withArgs(token.address, quote);
        });
        it("should not transfer tokens if quote is zero", async () => {
            // Set fee to 0
            await feeManager.setTradingFeeBps(0);
            const amount = ethers.utils.parseEther("100");

            const balanceBefore = await token.balanceOf(treasury.address);
            await token.approve(feeManager.address, amount);
            await feeManager.collectTradingFee(token.address, amount);
            const balanceAfter = await token.balanceOf(treasury.address);
            expect(balanceAfter).to.be.equal(balanceBefore);
        });
        it("should revert if the fee is not approved", async () => {
            const amount = ethers.utils.parseEther("100");
            await expect(feeManager.collectTradingFee(token.address, amount)).to.be.revertedWith("ERC20: insufficient allowance");
        });
    });
    describe("collectListingFee", () => {
        beforeEach(async () => {
            const FeeManager = await ethers.getContractFactory("FeeManager");
            feeManager = await FeeManager.deploy(treasury.address, 1000, ethers.utils.parseEther("0.02"), 2000);
        });
        it("should collect and redirect the fee to the treasury", async () => {
            const fee = await feeManager.listingFee();

            const balanceBefore = await token.balanceOf(treasury.address);
            await token.approve(feeManager.address, fee);
            await feeManager.collectListingFee(token.address);
            const balanceAfter = await token.balanceOf(treasury.address);
            expect(balanceAfter.sub(balanceBefore)).to.be.equal(fee);
        });
        it("should emit a FeeReceived event", async () => {
            const fee = await feeManager.listingFee();

            await token.approve(feeManager.address, fee);
            await expect(feeManager.collectListingFee(token.address)).to.emit(feeManager, "FeeReceived").withArgs(token.address, fee);
        });
        it("should not transfer tokens if listingFee is zero", async () => {
            // Set fee to 0
            await feeManager.setListingFee(0);

            const balanceBefore = await token.balanceOf(treasury.address);
            await feeManager.collectListingFee(token.address);
            const balanceAfter = await token.balanceOf(treasury.address);
            expect(balanceAfter).to.be.equal(balanceBefore);
        });
        it("should revert if the fee is not approved", async () => {
            await expect(feeManager.collectListingFee(token.address)).to.be.revertedWith("ERC20: insufficient allowance");
        });
    });
    describe("collectMigrationFee", () => {
        beforeEach(async () => {
            const FeeManager = await ethers.getContractFactory("FeeManager");
            feeManager = await FeeManager.deploy(treasury.address, 1000, ethers.utils.parseEther("0.02"), 2000);
        });
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
        beforeEach(async () => {
            const FeeManager = await ethers.getContractFactory("FeeManager");
            feeManager = await FeeManager.deploy(treasury.address, 1000, ethers.utils.parseEther("0.02"), 2000);
        });
        it("should set the fee", async () => {
            await feeManager.setTradingFeeBps(5000);
            expect(await feeManager.tradingFeeBps()).to.be.equal(5000);
        });
        it("should emit a TradingFeeSet event", async () => {
            await expect(feeManager.setTradingFeeBps(5000)).to.emit(feeManager, "TradingFeeSet").withArgs(5000);
        });
        it("should revert if the fee is greater than FEE_DIVISOR", async () => {
            const FEE_DIVISOR = await feeManager.FEE_DIVISOR();
            await expect(feeManager.setTradingFeeBps(FEE_DIVISOR.add(1))).to.be.revertedWithCustomError(
                feeManager,
                "FeeManager_AmountAboveFeeDivisor"
            );
        });
        it("should revert if the caller is not the owner", async () => {
            await expect(feeManager.connect(treasury).setTradingFeeBps(1000)).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });
    describe("setListingFee", () => {
        beforeEach(async () => {
            const FeeManager = await ethers.getContractFactory("FeeManager");
            feeManager = await FeeManager.deploy(treasury.address, 1000, ethers.utils.parseEther("0.02"), 2000);
        });
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
        beforeEach(async () => {
            const FeeManager = await ethers.getContractFactory("FeeManager");
            feeManager = await FeeManager.deploy(treasury.address, 1000, ethers.utils.parseEther("0.02"), 2000);
        });
        it("should set the fee", async () => {
            await feeManager.setMigrationFeeBps(5000);
            expect(await feeManager.migrationFeeBps()).to.be.equal(5000);
        });
        it("should emit a MigrationFeeSet event", async () => {
            await expect(feeManager.setMigrationFeeBps(5000)).to.emit(feeManager, "MigrationFeeSet").withArgs(5000);
        });
        it("should revert if the fee is greater than FEE_DIVISOR", async () => {
            const FEE_DIVISOR = await feeManager.FEE_DIVISOR();
            await expect(feeManager.setMigrationFeeBps(FEE_DIVISOR.add(1))).to.be.revertedWithCustomError(
                feeManager,
                "FeeManager_AmountAboveFeeDivisor"
            );
        });
        it("should revert if the caller is not the owner", async () => {
            await expect(feeManager.connect(treasury).setMigrationFeeBps(1000)).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });
    describe("setTreasury", () => {
        beforeEach(async () => {
            const FeeManager = await ethers.getContractFactory("FeeManager");
            feeManager = await FeeManager.deploy(treasury.address, 1000, ethers.utils.parseEther("0.02"), 2000);
        });
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
