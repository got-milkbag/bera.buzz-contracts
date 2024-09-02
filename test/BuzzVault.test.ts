import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract } from "ethers";

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
    const Vault = await ethers.getContractFactory("BuzzVault");
    vault = await Vault.connect(ownerSigner).deploy(factory.address);

    // Admin: Set Vault as the factory's vault & enable token creation
    await factory.connect(ownerSigner).setVault(vault.address);
    await factory.connect(ownerSigner).setAllowTokenCreation(true);
  });
  describe("constructor", () => {
    it("should set the factory address", async () => {
      expect(await vault.factory()).to.be.equal(factory.address);
    });
  });
  describe("createVestingSchedule", () => {
    beforeEach(async () => {});
    it("should revert if the arrays have different lengths", async () => {});
  });
});
