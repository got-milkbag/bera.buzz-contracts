import {expect} from "chai";
import {ethers} from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {Contract} from "ethers";

describe("BuzzVault Tests", () => {
    let ownerSigner: SignerWithAddress;
    let user1Signer: SignerWithAddress;
    let user2Signer: SignerWithAddress;
    let factory: Contract;
    let vault: Contract;
    let token: Contract;

    beforeEach(async () => {
        [ownerSigner, user1Signer, user2Signer] = await ethers.getSigners();

        // Deploy factory
        const Factory = await ethers.getContractFactory("BuzzTokenFactory");
        factory = await Factory.connect(ownerSigner).deploy();

        // Deploy Vault
        const Vault = await ethers.getContractFactory("BuzzVaultLinear");
        vault = await Vault.connect(ownerSigner).deploy(factory.address, ethers.constants.AddressZero);

        // Admin: Set Vault as the factory's vault & enable token creation
        await factory.connect(ownerSigner).setVault(vault.address, true);
        await factory.connect(ownerSigner).setAllowTokenCreation(true);

        // Create a token
        const tx = await factory.createToken("TEST", "TEST", vault.address);
        const receipt = await tx.wait();
        const tokenCreatedEvent = receipt.events?.find((x: any) => x.event === "TokenCreated");

        // Get token contract
        token = await ethers.getContractAt("BuzzToken", tokenCreatedEvent?.args?.token);
    });
    describe("constructor", () => {
        it("should set the factory address", async () => {
            expect(await vault.factory()).to.be.equal(factory.address);
        });
    });
    describe("registerToken", () => {
        beforeEach(async () => {});
        it("should register token transferring totalSupply", async () => {
            const tokenInfo = await vault.tokenInfo(token.address);
            expect(tokenInfo.tokenBalance).to.be.equal(await token.totalSupply());
            //expect(tokenInfo.beraBalance).to.be.equal(0);
            expect(tokenInfo.bexListed).to.be.equal(false);

            expect(tokenInfo.tokenBalance).to.be.equal(await token.balanceOf(vault.address));
        });
        it("should revert if caller is not factory", async () => {
            await expect(vault.connect(user1Signer).registerToken(factory.address, ethers.utils.parseEther("100"))).to.be.revertedWithCustomError(
                vault,
                "BuzzVault_Unauthorized"
            );
        });
    });
    describe("buy", () => {
        beforeEach(async () => {});
        it("should ", async () => {
            console.log(await vault.quote(token.address, ethers.utils.parseEther("0.01"), true));
        });
    });
});
