import {ethers} from "hardhat";
const hre = require("hardhat");

//CONFIG - bArtio
const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
const feeRecipient = "0x964757D7aB4C84ef2e477e6DA6757FBA03dDB4C7"; // Address the protocol receives fees at
const crocQueryAddress = "0x8685CE9Db06D40CBa73e3d09e6868FE476B5dC89";
const wberaHoneyLpToken = "0xd28d852cbcc68dcec922f6d5c7a8185dbaa104b7";
// protocol fee is hardcoded in vaults

// ReferralManager config
const directRefFeeBps = 1500; // 15% of protocol fee
const indirectRefFeeBps = 100; // fixed 1%
const payoutThreshold = 0;
const validUntil = Math.floor(Date.now() / 1000) + ONE_YEAR_IN_SECS;

// The deployer is also the owner

async function main() {
    //Deployers address
    const [deployer] = await ethers.getSigners();
    const deployerAddress = await deployer.getAddress();
    console.log(`Deployer's address (owner): `, deployerAddress);

    // Deploy BexPriceDecoder
    const BexPriceDecoder = await ethers.getContractFactory("BexPriceDecoder");
    const bexPriceDecoder = await BexPriceDecoder.deploy(wberaHoneyLpToken, crocQueryAddress);
    console.log("BexPriceDecoder deployed to:", bexPriceDecoder.address);

    // Deploy ReferralManager
    const ReferralManager = await ethers.getContractFactory("ReferralManager");
    const referralManager = await ReferralManager.deploy(directRefFeeBps, indirectRefFeeBps, validUntil, payoutThreshold);
    console.log("ReferralManager deployed to:", referralManager.address);

    // Deploy EventTracker
    const EventTracker = await ethers.getContractFactory("BuzzEventTracker");
    const eventTracker = await EventTracker.deploy([]);
    console.log("EventTracker deployed to:", eventTracker.address);

    // Deploy factory
    const Factory = await ethers.getContractFactory("BuzzTokenFactory");
    const factory = await Factory.deploy(eventTracker.address);
    console.log("Factory deployed to:", factory.address);

    // Deploy Linear Vault
    const Vault = await ethers.getContractFactory("BuzzVaultLinear");
    const vault = await Vault.deploy(feeRecipient, factory.address, referralManager.address, eventTracker.address, bexPriceDecoder.address);
    console.log("Linear Vault deployed to:", vault.address);

    // Deploy Exponential Vault
    const ExpVault = await ethers.getContractFactory("BuzzVaultExponential");
    const expVault = await ExpVault.deploy(feeRecipient, factory.address, referralManager.address, eventTracker.address, bexPriceDecoder.address);
    console.log("Exponential Vault deployed to:", expVault.address);

    // Admin: Set Vault in the ReferralManager
    await referralManager.setWhitelistedVault(vault.address, true);
    await referralManager.setWhitelistedVault(expVault.address, true);

    // Admin: Set event setter contracts in EventTracker
    await eventTracker.setEventSetter(vault.address, true);
    await eventTracker.setEventSetter(expVault.address, true);
    await eventTracker.setEventSetter(factory.address, true);

    // Admin: Set Vault as the factory's vault & enable token creation
    await factory.setVault(vault.address, true);
    await factory.setVault(expVault.address, true);

    await factory.setAllowTokenCreation(true);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
