import { BigNumber } from "ethers";
import {ethers} from "hardhat";
const hre = require("hardhat");

const CREATE_TOKEN_ABI = [
    "function createToken (string calldata name, string calldata symbol, address vault, bytes32 salt) external returns (address token)",
];

async function main() {
    const [deployer] = await ethers.getSigners();

    console.log("Creating tokens with the account:", deployer.address);

    const tokenFactoryAddr = "0x4A2E15159637A60a147D021BfC0F5FE4e049F22f";

    // change every deployment, note deployer is temp proxy and not msg.sender
    const salt = "0x00000000000000000000000000000ef97e7373f5806fd04e465cc1fd7e395ca1";
    const expVault = "0x2f39b10CdDF881E0eE96e4c4e8926D8dD7107307";

    //TODO: Update script
    const tokenFactoryContract = new ethers.Contract(tokenFactoryAddr, CREATE_TOKEN_ABI, deployer);
    const tx = await tokenFactoryContract.createToken("Test Token", "TT", expVault, salt);
    console.log(tx);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
