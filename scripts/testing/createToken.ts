import {ethers} from "hardhat";
const hre = require("hardhat");

const CREATE_TOKEN_ABI =
    [
        "function createToken (string memory name, string memory symbol, string memory description, string memory image, address vault, bytes32 salt) public returns (address)"
    ];

async function main() {
    const [deployer] = await ethers.getSigners();

    console.log(
        "Deploying contracts with the account:",
        deployer.address
    );

    const tokenFactoryAddr = "0xc70A03cfa01E77CDd9762fBF834c2D0AD60fCC3D"
    const tokenFactoryContract = new ethers.Contract(tokenFactoryAddr, CREATE_TOKEN_ABI, deployer);
    const tx = await tokenFactoryContract.createToken("Test Token", "TT", "Test Token Description", "https://test.com", "0x09E8bfbCF8852Ce3286f1a612B77E7C8CCF6C6ae", "0xa0000000000000000000000000245104a51489e68665a1189eef3f040b253fca");
    console.log(tx);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});