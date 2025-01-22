import {ethers} from "hardhat";
const hre = require("hardhat");
import * as TokenFactory from "../../typechain-types/factories/contracts/BuzzTokenFactory__factory";

//CONFIG - bArtio
const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
const bexWeightedPoolFactory = "0x09836Ff4aa44C9b8ddD2f85683aC6846E139fFBf";
const bexVault = "0x9C8a5c82e797e074Fe3f121B326b140CEC4bcb33";
const feeRecipient = "0x964757D7aB4C84ef2e477e6DA6757FBA03dDB4C7"; // Address the protocol receives fees at
const create3Address = "0xE088cf94c8C0200022E15e86fc4F9f3A4B2F6e5c";
const wberaAddress = "0x6969696969696969696969696969696969696969";

const highlightsSuffix = ethers.utils.arrayify("0x1bee");


// protocol fee is hardcoded in vaults

// Factory config
// Wbera as base token config:
const baseTokenMinReserveAmount = ethers.utils.parseEther("0.001");
const baseTokenMinRaiseAmount = ethers.utils.parseEther("0.1");

// ReferralManager config
const directRefFeeBps = 1500; // 15% of protocol fee
const indirectRefFeeBps = 100; // fixed 1%
const listingFee = ethers.utils.parseEther("0.002");
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

    // Deploy FeeManager
    const FeeManager = await ethers.getContractFactory("FeeManager");
    const feeManager = await FeeManager.deploy(feeRecipient, tradingFeeBps, listingFee, migrationFeeBps);
    console.log("FeeManager deployed to:", feeManager.address);

    // Deploy ReferralManager
    const ReferralManager = await ethers.getContractFactory("ReferralManager");
    const referralManager = await ReferralManager.deploy(directRefFeeBps, indirectRefFeeBps, validUntil, [wberaAddress], [payoutThreshold]);
    console.log("ReferralManager deployed to:", referralManager.address);

    // Deploy Factory via Create3
    const abi = TokenFactory.BuzzTokenFactory__factory.abi;
    const factoryBytecode = TokenFactory.BuzzTokenFactory__factory.bytecode;
    const factory = new ethers.ContractFactory(abi, factoryBytecode);
    const creationCode = factory.bytecode;
    // change salt for each new deployment
    const salt = "0x200000000000000000000000000015fca116f803b9ac9849772f2af2e9f1305d";
    const packedBytecode = ethers.utils.solidityPack(
        ["bytes", "bytes"],
        [creationCode, ethers.utils.defaultAbiCoder.encode(["address", "address", "address"], [deployerAddress, create3Address, feeManager.address])]
    );
    const create3FactoryContract = new ethers.Contract(create3Address, DEPLOY_ABI, deployer);
    const tx = await create3FactoryContract.deploy(salt, packedBytecode);
    const deployedAddress = await create3FactoryContract.getDeployed(deployer.address, salt);
    console.log("Factory deployed to:", deployedAddress);
    await tx.wait();
    const factoryInstance = await ethers.getContractAt("BuzzTokenFactory", deployedAddress);

    // Deploy BexLiquidityManager
    const BexLiquidityManager = await ethers.getContractFactory("BexLiquidityManager");
    const bexLiquidityManager = await BexLiquidityManager.deploy(bexWeightedPoolFactory, bexVault);
    console.log("BexLiquidityManager deployed to:", bexLiquidityManager.address);

    // // Deploy Linear Vault
    // const Vault = await ethers.getContractFactory("BuzzVaultLinear");
    // const vault = await Vault.deploy(
    //     feeRecipient,
    //     factoryInstance.address,
    //     referralManager.address,
    //     bexLiquidityManager.address
    // );
    // console.log("Linear Vault deployed to:", vault.address);

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
    const highlightsManager = await HighlightsManager.deploy(feeRecipient, hardCap, highlightsBaseFee, coolDownPeriod, highlightsSuffix);
    console.log("HighlightsManager deployed to:", highlightsManager.address);

    // Admin: Set Vault in the ReferralManager
    // await referralManager.setWhitelistedVault(vault.address, true);
    await referralManager.setWhitelistedVault(expVault.address, true);

    // Admin: Whitelist base token in Factory
    await factoryInstance.setAllowedBaseToken(wberaAddress, baseTokenMinReserveAmount, baseTokenMinRaiseAmount, true);

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
