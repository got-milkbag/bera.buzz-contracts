import {ethers} from "hardhat";
const hre = require("hardhat");
import * as TokenFactory from "../../typechain-types/factories/contracts/BuzzTokenFactory__factory.ts";

const create3Address = "0x93FEC2C00BfE902F733B57c5a6CeeD7CD1384AE1";

const DEPLOY_ABI =
    [
        "function deploy (bytes32 salt, bytes memory creationCode) public returns (address deployed)"
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
    const salt = "0x5c0000000000000000000000001578d16e2b59db56dbe8683dd21a576b66d931";
    const eventTracker = "0xE394411B1fD404112a510c8a80126c5e089aF236";

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
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
