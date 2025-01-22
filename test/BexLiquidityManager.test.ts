import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract } from "ethers";
import { expect } from "chai";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";

describe("BexLiquidityManager Tests", () => {
    const bexWeightedPoolFactory = "0x09836Ff4aa44C9b8ddD2f85683aC6846E139fFBf";
    const bexVault = "0x9C8a5c82e797e074Fe3f121B326b140CEC4bcb33";

    let ownerSigner: SignerWithAddress;
    let user1Signer: SignerWithAddress;
    let beraWhale: SignerWithAddress;
    let bexLiquidityManager: Contract;
    let token: Contract;
    let wbera: Contract;

    beforeEach(async () => {
        [ownerSigner, user1Signer] = await ethers.getSigners();
        beraWhale = await ethers.getImpersonatedSigner("0x8a73D1380345942F1cb32541F1b19C40D8e6C94B");

        //Deploy WBera Mock
        const WBera = await ethers.getContractFactory("WBERA");
        wbera = await WBera.connect(ownerSigner).deploy();

        // Deploy BexLiquidityManager
        const BexLiquidityManager = await ethers.getContractFactory("BexLiquidityManager");
        bexLiquidityManager = await BexLiquidityManager.deploy(bexWeightedPoolFactory, bexVault);
        await bexLiquidityManager.addVaults([beraWhale.address]);

        // Deploy token
        const Token = await ethers.getContractFactory("BuzzToken");
        token = await Token.connect(beraWhale).deploy(
            "Test 1",
            "TST1",
            ethers.utils.parseEther("1000000000"),
            beraWhale.address,
            beraWhale.address
        );

        console.log("Token address: ", token.address);

        await token.connect(beraWhale).approve(bexLiquidityManager.address, ethers.utils.parseEther("1000000000"));

        // Convert Bera to WBera
        await wbera.connect(beraWhale).deposit({ value: ethers.utils.parseEther("2300") });
        await wbera.connect(beraWhale).approve(bexLiquidityManager.address, ethers.utils.parseEther("2300"));
    });
    describe("createPoolAndAdd", () => {
        it("should create a pool and add liquidity", async () => {
            // NOTE: baseAmount (2nd argument) is equivelant of 69k USD if 1 Bera = 30 USD
            expect(await bexLiquidityManager
                .connect(beraWhale)
                .createPoolAndAdd(token.address, wbera.address, ethers.utils.parseEther("2300"), ethers.utils.parseEther("20000000")))
            .to.emit(bexLiquidityManager, "BexListed")
            .withArgs(anyValue, wbera.address, token.address, ethers.utils.parseEther("2300"), ethers.utils.parseEther("20000000"));
            console.log("Bera balance in pool after transition to Bex: ", await ethers.provider.getBalance(bexLiquidityManager.address));
            console.log("WBERA balance in pool after transition to Bex: ", await wbera.balanceOf(bexLiquidityManager.address));
            console.log("Token balance in pool after transition to Bex: ", await token.balanceOf(bexLiquidityManager.address));
        });
        it("should revert if non authorized address tries to create pool", async () => {
            await expect(
                bexLiquidityManager
                    .connect(user1Signer)
                    .createPoolAndAdd(token.address, wbera.address, ethers.utils.parseEther("2300"), ethers.utils.parseEther("20000000"))
            ).to.be.revertedWithCustomError(bexLiquidityManager, "BexLiquidityManager_Unauthorized");
        });
    });
    describe("addVaults", () => {
        it("should add vaults", async () => {
            expect(await bexLiquidityManager.addVaults([user1Signer.address]))
            .to.emit(bexLiquidityManager, "VaultAdded")
            .withArgs(user1Signer.address);
        });
        it("should revert if non owner tries to add vaults", async () => {
            await expect(bexLiquidityManager.connect(user1Signer).addVaults([user1Signer.address])).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );
        });
        it("should revert if vault already in whitelist", async () => {
            await bexLiquidityManager.addVaults([user1Signer.address]);
            await expect(bexLiquidityManager.addVaults([user1Signer.address])).to.be.revertedWithCustomError(
                bexLiquidityManager,
                "BexLiquidityManager_VaultAlreadyInWhitelist"
            );
        });
    });
    describe("removeVaults", () => {
        it("should remove vaults", async () => {
            await bexLiquidityManager.addVaults([user1Signer.address]);
            expect(await bexLiquidityManager.removeVaults([user1Signer.address]))
            .to.emit(bexLiquidityManager, "VaultRemoved")
            .withArgs(user1Signer.address);
        });
        it("should revert if non owner tries to remove vaults", async () => {
            await expect(bexLiquidityManager.connect(user1Signer).removeVaults([user1Signer.address])).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );
        });
        it("should revert if vault not in whitelist", async () => {
            await expect(bexLiquidityManager.removeVaults([user1Signer.address])).to.be.revertedWithCustomError(
                bexLiquidityManager,
                "BexLiquidityManager_VaultNotInWhitelist"
            );
        });
    });
});
