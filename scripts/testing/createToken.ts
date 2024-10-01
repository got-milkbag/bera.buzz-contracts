import {ethers} from "hardhat";
const hre = require("hardhat");

const CREATE_TOKEN_ABI =
    [
        "function createToken (string calldata name, string calldata symbol, string calldata description, string calldata image, address vault, bytes32 salt) external returns (address token)"
    ];

async function main() {
    const [deployer] = await ethers.getSigners();

    console.log(
        "Creating tokens with the account:",
        deployer.address
    );

    const tokenFactoryAddr = "0xA61Abb8a2cD1b74E3c83C7D48bb2c0d388189fc3";

    // change every deployment, note deployer is temp proxy and not msg.sender
    const salt = "0x00000000000000000000000000000ef97e7373f5806fd04e465cc1fd7e395ca1";
    const linearVault = "0xF23a123676028E44117440eC2DFC5fa15c5c5f81";

    const tokenFactoryContract = new ethers.Contract(tokenFactoryAddr, CREATE_TOKEN_ABI, deployer);
    const tx = await tokenFactoryContract.createToken("Test Token", "TT", "Test Token Description", "https://test.com", linearVault, salt);
    console.log(tx);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});