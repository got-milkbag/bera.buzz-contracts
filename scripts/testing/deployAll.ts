import {ethers} from "hardhat";
const hre = require("hardhat");
import * as TokenFactory from "../../typechain-types/factories/contracts/BuzzTokenFactory__factory";

//CONFIG - bArtio
const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
const feeRecipient = "0x964757D7aB4C84ef2e477e6DA6757FBA03dDB4C7"; // Address the protocol receives fees at
const crocQueryAddress = "0x8685CE9Db06D40CBa73e3d09e6868FE476B5dC89";
const wberaHoneyLpToken = "0xd28d852cbcc68dcec922f6d5c7a8185dbaa104b7";
const create3Address = "0x93FEC2C00BfE902F733B57c5a6CeeD7CD1384AE1";
const crocSwapDex = "0xAB827b1Cc3535A9e549EE387A6E9C3F02F481B49";
const wberaAddress = "0x7507c1dc16935B82698e4C63f2746A2fCf994dF8";

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

    // Deploy BexPriceDecoder
    const BexPriceDecoder = await ethers.getContractFactory("BexPriceDecoder");
    const bexPriceDecoder = await BexPriceDecoder.deploy(crocQueryAddress, [wberaAddress], [wberaHoneyLpToken]);
    console.log("BexPriceDecoder deployed to:", bexPriceDecoder.address);

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
    const bexLiquidityManager = await BexLiquidityManager.deploy(crocSwapDex);
    console.log("BexLiquidityManager deployed to:", bexLiquidityManager.address);

    // // Deploy Linear Vault
    // const Vault = await ethers.getContractFactory("BuzzVaultLinear");
    // const vault = await Vault.deploy(
    //     feeRecipient,
    //     factoryInstance.address,
    //     referralManager.address,
    //     bexPriceDecoder.address,
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
    const highlightsManager = await HighlightsManager.deploy(feeRecipient, hardCap, highlightsBaseFee, coolDownPeriod);
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
