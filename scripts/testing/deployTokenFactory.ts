import {ethers} from "hardhat";
const hre = require("hardhat");
import * as TokenFactory from "../../typechain-types/factories/contracts/BuzzTokenFactory__factory.ts";

const create3Address = "0x93FEC2C00BfE902F733B57c5a6CeeD7CD1384AE1";
const linearVault = "0x09E8bfbCF8852Ce3286f1a612B77E7C8CCF6C6ae";
const expVault = "0x8a8BF2feF202127A9B957c0F376d25A68344Be2b";
const eventTracker = "0xE394411B1fD404112a510c8a80126c5e089aF236";

const DEPLOY_ABI =
    [
        "function deploy (bytes32 salt, bytes memory creationCode) public returns (address deployed)",
        "function getDeployed (address deployer, bytes32 salt) public view returns (address deployed)"
    ];

async function main() {
    const [deployer] = await ethers.getSigners();

    console.log(
        "Deploying contracts with the account:",
        deployer.address
    );

    const abi = TokenFactory.BuzzTokenFactory__factory.abi;
    const factoryBytecode = TokenFactory.BuzzTokenFactory__factory.bytecode;
    const factory = new ethers.ContractFactory(abi, factoryBytecode);
    const creationCode = factory.bytecode;


    // change salt for each new deployment
    const salt = "0x2000000000000000000000000017e481daa1e92c233b6a774260d53b6f5e25c4";

    const packedBytecode = ethers.utils.solidityPack(
        ["bytes", "bytes"],
        [
            creationCode,
            ethers.utils.defaultAbiCoder.encode(["address", "address", "address"], [eventTracker, deployer.address, create3Address])
        ]
    );

    const create3FactoryContract = new ethers.Contract(create3Address, DEPLOY_ABI, deployer);
    const tx = await create3FactoryContract.deploy(salt, packedBytecode);
    console.log(tx);

    const deployedAddress = await create3FactoryContract.getDeployed(deployer.address, salt);
    console.log(deployedAddress, "Deployed TokenFactory address");
    await tx.wait();

    const tokenFactoryContract = new ethers.Contract(deployedAddress, abi, deployer);

    const tx1 = await tokenFactoryContract.setVault(linearVault, true);
    tx1.wait();

    const tx2 = await tokenFactoryContract.setVault(expVault, true);
    tx2.wait();

    const tx3 = await tokenFactoryContract.setAllowTokenCreation(true);
    tx3.wait();

    console.log(tx1);
    console.log(tx2);
    console.log(tx3);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
