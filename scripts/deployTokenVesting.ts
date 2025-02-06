import { ethers } from "hardhat";

async function main() {
  //Deployers address
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  console.log(`Deployer's address (owner): `, deployerAddress);

  // Deploy Token Vesting
  const TokenVesting = await ethers.getContractFactory("TokenVesting");
  const tokenVesting = await TokenVesting.deploy();
  console.log("Token Vesting contract deployed to:", tokenVesting.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
