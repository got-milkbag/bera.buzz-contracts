import {ethers} from "hardhat";
const hre = require("hardhat");
import {BigNumber, Contract} from "ethers";

let bexLiquidityManager: Contract;
const bexWeightedPoolFactory = "0x09836Ff4aa44C9b8ddD2f85683aC6846E139fFBf";
const bexVault = "0x9C8a5c82e797e074Fe3f121B326b140CEC4bcb33";

async function main() {
    //TODO: Update script
    const [deployer] = await ethers.getSigners();

    console.log("Creating tokens with the account:", deployer.address);

    // Deploy token
    const Token = await ethers.getContractFactory("BuzzToken");
    const token = await Token.deploy("Test 1", "TST1", ethers.utils.parseEther("1000000"), deployer.address);

    // Deploy token
    const Token1 = await ethers.getContractFactory("BuzzToken");
    const token1 = await Token.deploy("Test 2", "TST2", ethers.utils.parseEther("1000000"), deployer.address);

    // Deploy BexLiquidityManager
    const BexLiquidityManager = await ethers.getContractFactory("BexLiquidityManager");
    bexLiquidityManager = await BexLiquidityManager.deploy(bexWeightedPoolFactory, bexVault);
    await bexLiquidityManager.addVaults([deployer.address]);

    console.log("Token address: ", token.address);
    console.log("BexLiquidityManager address: ", bexLiquidityManager.address);

    const approveTx = await token.connect(deployer).approve(bexLiquidityManager.address, ethers.utils.parseEther("1000000"));

    await approveTx.wait();

    console.log(approveTx);

    const approveTx1 = await token1.connect(deployer).approve(bexLiquidityManager.address, ethers.utils.parseEther("1000000"));
    await approveTx1.wait();
    console.log(approveTx1);

    const tx = await bexLiquidityManager.createPoolAndAdd(token.address, token1.address, deployer.address, ethers.utils.parseEther("1000000"), ethers.utils.parseEther("0.001"));

    console.log(tx);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
