import {ethers} from "hardhat";
const hre = require("hardhat");
import { Contract } from "ethers";

let bexLiquidityManager: Contract;
const crocSwapDex = "0xAB827b1Cc3535A9e549EE387A6E9C3F02F481B49";

async function main() {
    const [deployer] = await ethers.getSigners();

    console.log(
        "Creating tokens with the account:",
        deployer.address
    );

    // Deploy token
    const Token = await ethers.getContractFactory("BuzzToken");
    const token = await Token.deploy("Test 1", "TST1", "Desc", "ipfs://", ethers.utils.parseEther("1000000"), deployer.address);

    // Deploy BexLiquidityManager
    const BexLiquidityManager = await ethers.getContractFactory("BexLiquidityManager");
    bexLiquidityManager = await BexLiquidityManager.deploy(crocSwapDex);

    console.log("Token address: ", token.address);
    console.log("BexLiquidityManager address: ", bexLiquidityManager.address);

    const approveTx = await token.connect(deployer).approve(bexLiquidityManager.address, ethers.utils.parseEther("100"));

    await approveTx.wait();

    console.log(approveTx);

    /*
    const token1 = await Token.deploy("Test 2", "TST2", "Desc", "ipfs://", ethers.utils.parseEther("1000000"), deployer.address);

    console.log("Token1 address: ", token1.address);
    console.log("BexLiquidityManager address: ", bexLiquidityManager.address);

    const approveTx1 = await token1.connect(deployer).approve(bexLiquidityManager.address, ethers.utils.parseEther("100"));

    await approveTx1.wait();

    console.log(approveTx1);
    */

    const tx = await bexLiquidityManager.createPoolAndAdd(token.address, ethers.utils.parseEther("50"), {
        value: ethers.utils.parseEther("0.01")
    });

    //await tx.wait();

    console.log(tx);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});