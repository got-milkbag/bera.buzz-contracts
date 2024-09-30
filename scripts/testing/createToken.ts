import {ethers} from "hardhat";
const hre = require("hardhat");

const CREATE_TOKEN_ABI =
    [
        "function createToken (string memory name, string memory symbol, string memory description, string memory image, address vault, bytes32 salt) public returns (address)"
    ];

async function main() {
    const [deployer] = await ethers.getSigners();

    console.log(
        "Creating tokens with the account:",
        deployer.address
    );

    const tokenFactoryAddr = "0x650B73A529ad84dbD07f69D9d930Db58Fc3688eD";

    // change every deployment, note deployer is temp proxy and not msg.sender
    const salt = "0x2000000000000000000000000017e481daa1e92c233b6a774260d53b6f5e25d3";

    const tokenFactoryContract = new ethers.Contract(tokenFactoryAddr, CREATE_TOKEN_ABI, deployer);
    const tx = await tokenFactoryContract.createToken("Test Token", "TT", "Test Token Description", "https://test.com", "0x09E8bfbCF8852Ce3286f1a612B77E7C8CCF6C6ae", salt);
    console.log(tx);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});