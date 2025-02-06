import {ethers} from "hardhat";
const hre = require("hardhat");
import * as TokenFactory from "../typechain-types/factories/contracts/BuzzTokenFactory__factory";

//CONFIG - bArtio
const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
const bexWeightedPoolFactory = "0xa966fA8F2d5B087FFFA499C0C1240589371Af409";
const bexVault = "0x4Be03f781C497A489E3cB0287833452cA9B9E80B";
const feeRecipient = "0xa5eb0f07d8496bce1cd7e215e9b37f9ab66c46b2"; // Address the protocol receives fees at
//const create3Address = "0xE088cf94c8C0200022E15e86fc4F9f3A4B2F6e5c";
const wberaAddress = "0x6969696969696969696969696969696969696969";
const nectAddress = "0x1cE0a25D13CE4d52071aE7e02Cf1F6606F4C79d3";
const ibgtAddress = "0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b";

const highlightsSuffix = ethers.utils.arrayify("0x1bee");


// protocol fee is hardcoded in vaults

// Factory config
// Wbera as base token config:
const baseTokenMinReserveAmount = ethers.utils.parseEther("0.001");
const baseTokenMinRaiseAmount = ethers.utils.parseEther("0.1");

// ReferralManager config
const directRefFeeBps = 1500; // 15% of protocol fee
const indirectRefFeeBps = 100; // fixed 1%
const listingFee = ethers.utils.parseEther("0.2");
const tradingFeeBps = 100; // 1% trading fee
const migrationFeeBps = 420; // 4.2% migration fee
const payoutThreshold = 0;
const validUntil = Math.floor(Date.now() / 1000) + ONE_YEAR_IN_SECS;

// HighlightsManager config
const highlightsBaseFee = ethers.utils.parseEther("0.0005"); // base fee per second for highlighting
const hardCap = 3600; // 1 hour in seconds
const coolDownPeriod = 60 * 60 * 24; // 1 day

// The deployer is also the owner

const DEPLOY_ABI = [
    "function deploy (bytes32 salt, bytes memory creationCode) public returns (address deployed)",
    "function getDeployed (address deployer, bytes32 salt) public view returns (address deployed)",
];

//TODO: Update script
async function main() {
    //Deployers address
    const [deployer] = await ethers.getSigners();
    const deployerAddress = await deployer.getAddress();
    console.log(`Deployer's address (owner): `, deployerAddress);

    // Deploy CREATE3Factory
    const CREATE3Factory = await ethers.getContractFactory("CREATE3Factory");
    const create3Factory = await CREATE3Factory.deploy();
    console.log("CREATE3Factory deployed to:", create3Factory.address);

    // Deploy FeeManager
    const FeeManager = await ethers.getContractFactory("FeeManager");
    const feeManager = await FeeManager.deploy(feeRecipient, tradingFeeBps, listingFee, migrationFeeBps);
    console.log("FeeManager deployed to:", feeManager.address);

    // Deploy ReferralManager
    const ReferralManager = await ethers.getContractFactory("ReferralManager");
    const referralManager = await ReferralManager.deploy(directRefFeeBps, indirectRefFeeBps, validUntil, [wberaAddress], [payoutThreshold]);
    console.log("ReferralManager deployed to:", referralManager.address);

    // Deploy Factory
    const Factory = await ethers.getContractFactory("BuzzTokenFactory");
    const factoryInstance = await Factory.deploy(deployerAddress, create3Factory.address, feeManager.address, highlightsSuffix);
    console.log("Factory deployed to:", factoryInstance.address);

    // Deploy BexLiquidityManager
    const BexLiquidityManager = await ethers.getContractFactory("BexLiquidityManager");
    const bexLiquidityManager = await BexLiquidityManager.deploy(bexWeightedPoolFactory, bexVault);
    console.log("BexLiquidityManager deployed to:", bexLiquidityManager.address);

    // Deploy Exponential Vault
    const ExpVault = await ethers.getContractFactory("BuzzVaultExponential");
    const expVault = await ExpVault.deploy(
        feeManager.address,
        factoryInstance.address,
        referralManager.address,
        bexLiquidityManager.address,
        wberaAddress
    );
    console.log("Exponential Vault deployed to:", expVault.address);

    await bexLiquidityManager.addVaults([expVault.address]);

    // Deploy HighlighstManager
    const HighlightsManager = await ethers.getContractFactory("HighlightsManager");
    const highlightsManager = await HighlightsManager.deploy(feeRecipient, factoryInstance.address, hardCap, highlightsBaseFee, coolDownPeriod);
    console.log("HighlightsManager deployed to:", highlightsManager.address);

    // Admin: Set Vault in the ReferralManager
    // await referralManager.setWhitelistedVault(vault.address, true);
    await referralManager.setWhitelistedVault(expVault.address, true);

    // Admin: Whitelist base token in Factory
    await factoryInstance.setAllowedBaseToken(wberaAddress, baseTokenMinReserveAmount, baseTokenMinRaiseAmount, true);

    // Admin: Whitelist base token in Factory
    await factoryInstance.setAllowedBaseToken(nectAddress, baseTokenMinReserveAmount, baseTokenMinRaiseAmount, true);

    // Admin: Whitelist base token in Factory
    await factoryInstance.setAllowedBaseToken(ibgtAddress, baseTokenMinReserveAmount, baseTokenMinRaiseAmount, true);

    // Admin: Set Vault as the factory's vault & enable token creation
    // await factoryInstance.setVault(vault.address, true);
    await factoryInstance.setVault(expVault.address, true);

    await factoryInstance.setAllowTokenCreation(true);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
