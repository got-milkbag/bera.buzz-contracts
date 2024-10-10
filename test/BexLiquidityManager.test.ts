import {expect} from "chai";
import {ethers} from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import * as helpers from "@nomicfoundation/hardhat-network-helpers";
import {formatBytes32String} from "ethers/lib/utils";
import {BigNumber, Contract} from "ethers";

describe("BexLiquidityManager Tests", () => {
    const crocSwapDex = "0xAB827b1Cc3535A9e549EE387A6E9C3F02F481B49";

    let ownerSigner: SignerWithAddress;
    let user1Signer: SignerWithAddress;
    let beraWhale: SignerWithAddress;
    let factory: Contract;
    let bexLiquidityManager: Contract;
    let token: Contract;

    beforeEach(async () => {
        [ownerSigner, user1Signer] = await ethers.getSigners();
        beraWhale = await ethers.getImpersonatedSigner("0x8a73D1380345942F1cb32541F1b19C40D8e6C94B");

        // Deploy BexLiquidityManager
        const BexLiquidityManager = await ethers.getContractFactory("BexLiquidityManager");
        bexLiquidityManager = await BexLiquidityManager.deploy(crocSwapDex);

        // Deploy token
        const Token = await ethers.getContractFactory("BuzzToken");
        token = await Token.connect(beraWhale).deploy("Test 1", "TST1", "Desc", "ipfs://", ethers.utils.parseEther("1000000000"), beraWhale.address);

        console.log("Token address: ", token.address);

        await token.approve(bexLiquidityManager.address, ethers.utils.parseEther("1000000000"));
    });
    describe("constructor", () => {
        it("should create a pool and add liquidity", async () => {
            await bexLiquidityManager
                .connect(beraWhale)
                .createPoolAndAdd(token.address, ethers.utils.parseEther("1000000000"), ethers.utils.parseEther("0.5"), {
                    value: ethers.utils.parseEther("1000000"),
                });
            console.log("Bera balance in pool after: ", await ethers.provider.getBalance(bexLiquidityManager.address));
        });
    });
});
