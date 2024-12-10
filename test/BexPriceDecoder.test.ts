import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, Contract } from "ethers";
import { expect } from "chai";

describe("BexPriceDecoder Tests", () => {
    let ownerSigner: SignerWithAddress;
    let user1Signer: SignerWithAddress;
    let bexPriceDecoder: Contract;
    let wBera: Contract;

    const bexLpTokenAddress = "0xd28d852cbcc68dcec922f6d5c7a8185dbaa104b7";
    const crocQueryAddress = "0x8685CE9Db06D40CBa73e3d09e6868FE476B5dC89";
    const honeyTokenAddress = "0x0E4aaF1351de4c0264C5c7056Ef3777b41BD8e03";
    const bexHoneyUsdcLpAddress = "0xD69ADb6FB5fD6D06E6ceEc5405D95A37F96E3b96";
    const usdcAddress = "0xd6D83aF58a19Cd14eF3CF6fe848C9A4d21e5727c";
    const usdcHoneyIdx = 36000;
    const bexPriceOnCurrentBlock = BigNumber.from("17329796811204929055");

    beforeEach(async () => {
        [ownerSigner, user1Signer] = await ethers.getSigners();

        //Deploy WBera Mock
        const WBera = await ethers.getContractFactory("WBERA");
        wBera = await WBera.connect(ownerSigner).deploy();

        // Deploy BexPriceDecoder
        const BexPriceDecoder = await ethers.getContractFactory("BexPriceDecoder");
        bexPriceDecoder = await BexPriceDecoder.connect(ownerSigner).deploy(
            crocQueryAddress,
            [wBera.address],
            [bexLpTokenAddress]
        );
    });

    describe("addLpTokens", () => {
        it("should add LP tokens", async () => {
            await expect(bexPriceDecoder.connect(ownerSigner).addLpTokens(
                [honeyTokenAddress],
                [bexHoneyUsdcLpAddress]
            )).to.emit(bexPriceDecoder, "LpTokenAdded")
            .withArgs(
                bexHoneyUsdcLpAddress,
                honeyTokenAddress,
                usdcAddress,
                usdcHoneyIdx,
            );

            const lpTokens = await bexPriceDecoder.lpTokens(honeyTokenAddress);

            expect(lpTokens[0]).to.be.equal(bexHoneyUsdcLpAddress);
            expect(lpTokens[1]).to.be.equal(honeyTokenAddress);
            expect(lpTokens[2]).to.be.equal(usdcAddress);
            expect(lpTokens[3]).to.be.equal(usdcHoneyIdx);
        });

        it("should revert if not called by owner", async () => {
            await expect(bexPriceDecoder.connect(user1Signer).addLpTokens(
                [honeyTokenAddress],
                [bexHoneyUsdcLpAddress]
            )).to.be.revertedWith("Ownable: caller is not the owner");
        });

        it("should revert if lpTokens length is not equal to lpTokensAddresses length", async () => {
            await expect(bexPriceDecoder.connect(ownerSigner).addLpTokens(
                [honeyTokenAddress],
                [bexHoneyUsdcLpAddress, bexHoneyUsdcLpAddress]
            )).to.be.revertedWithCustomError(bexPriceDecoder, "BexPriceDecoder_TokensLengthMismatch");
        })

        it("should revert if one of the tokens is already on the mapping", async () => {
            await bexPriceDecoder.connect(ownerSigner).addLpTokens(
                [honeyTokenAddress],
                [bexHoneyUsdcLpAddress]
            );

            await expect(bexPriceDecoder.connect(ownerSigner).addLpTokens(
                [honeyTokenAddress],
                [bexHoneyUsdcLpAddress]
            )).to.be.revertedWithCustomError(bexPriceDecoder, "BexPriceDecoder_TokenAlreadyExists");
        });

        it("should revert if one of the input tokens is address(0)", async () => {
            await expect(bexPriceDecoder.connect(ownerSigner).addLpTokens(
                [honeyTokenAddress, ethers.constants.AddressZero],
                [bexHoneyUsdcLpAddress, bexHoneyUsdcLpAddress]
            )).to.be.revertedWithCustomError(bexPriceDecoder, "BexPriceDecoder_TokenAddressZero");
        });

        it("should revert if one of the input lpTokens is address(0)", async () => {
            await expect(bexPriceDecoder.connect(ownerSigner).addLpTokens(
                [honeyTokenAddress, honeyTokenAddress],
                [bexHoneyUsdcLpAddress, ethers.constants.AddressZero]
            )).to.be.revertedWithCustomError(bexPriceDecoder, "BexPriceDecoder_TokenAddressZero");
        });
    });
    describe("getPrice", () => {
        it("should get price", async () => {
            const price = await bexPriceDecoder.getPrice(wBera.address);

            expect(price).to.be.equal(bexPriceOnCurrentBlock);
        });

        it("should revert if token is not on the mapping", async () => {
            await expect(bexPriceDecoder.connect(ownerSigner).getPrice(honeyTokenAddress))
            .to.be.revertedWithCustomError(bexPriceDecoder, "BexPriceDecoder_TokenDoesNotExist");
        });

        it("should revert if token is address(0)", async () => {
            await expect(bexPriceDecoder.connect(ownerSigner).getPrice(ethers.constants.AddressZero))
            .to.be.revertedWithCustomError(bexPriceDecoder, "BexPriceDecoder_TokenAddressZero");
        });
    });
});
