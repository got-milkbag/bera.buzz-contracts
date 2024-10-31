import {expect} from "chai";
import {ethers} from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import * as helpers from "@nomicfoundation/hardhat-network-helpers";
import {BigNumber, Contract} from "ethers";
import {formatBytes32String} from "ethers/lib/utils";

describe("BuzzTokenFactory Tests", () => {
    const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
    let feeRecipient: string;

    let ownerSigner: SignerWithAddress;
    let user1Signer: SignerWithAddress;
    let user2Signer: SignerWithAddress;
    let feeRecipientSigner: SignerWithAddress;
    let factory: Contract;
    let vault: Contract;
    let token: Contract;
    let referralManager: Contract;
    let expVault: Contract;
    let bexLpToken: Contract;
    let crocQuery: Contract;
    let bexPriceDecoder: Contract;
    let create3Factory: Contract;
    let bexLiquidityManager: Contract;
    let treasuryBalanceBefore: BigNumber;

    const directRefFeeBps = 1500; // 15% of protocol fee
    const indirectRefFeeBps = 100; // fixed 1%
    const listingFee = ethers.utils.parseEther("0.002");
    const payoutThreshold = 0;
    const crocSwapDexAddress = "0xAB827b1Cc3535A9e549EE387A6E9C3F02F481B49";
    let validUntil: number;

    beforeEach(async () => {
        validUntil = (await helpers.time.latest()) + ONE_YEAR_IN_SECS;

        [ownerSigner, user1Signer, user2Signer, feeRecipientSigner] = await ethers.getSigners();
        feeRecipient = feeRecipientSigner.address;

        // Deploy mock create3factory
        const Create3Factory = await ethers.getContractFactory("CREATE3FactoryMock");
        create3Factory = await Create3Factory.connect(ownerSigner).deploy();

        // Deploy mock BexLpToken
        const BexLpToken = await ethers.getContractFactory("BexLPTokenMock");
        bexLpToken = await BexLpToken.connect(ownerSigner).deploy(36000, ethers.constants.AddressZero, ethers.constants.AddressZero);

        //Deploy mock ICrocQuery
        const ICrocQuery = await ethers.getContractFactory("CrocQueryMock");
        crocQuery = await ICrocQuery.connect(ownerSigner).deploy(ethers.BigNumber.from("83238796252293901415"));

        // Deploy BexPriceDecoder
        const BexPriceDecoder = await ethers.getContractFactory("BexPriceDecoder");
        bexPriceDecoder = await BexPriceDecoder.connect(ownerSigner).deploy(bexLpToken.address, crocQuery.address);

        // Deploy ReferralManager
        const ReferralManager = await ethers.getContractFactory("ReferralManager");
        referralManager = await ReferralManager.connect(ownerSigner).deploy(directRefFeeBps, indirectRefFeeBps, validUntil, payoutThreshold);

        // Deploy factory
        const Factory = await ethers.getContractFactory("BuzzTokenFactory");
        factory = await Factory.connect(ownerSigner).deploy(ownerSigner.address, create3Factory.address, feeRecipient, listingFee);
        // Deploy liquidity manager
        const BexLiquidityManager = await ethers.getContractFactory("BexLiquidityManager");
        bexLiquidityManager = await BexLiquidityManager.connect(ownerSigner).deploy(crocSwapDexAddress);

        // Deploy Linear Vault
        /*const Vault = await ethers.getContractFactory("BuzzVaultLinear");
        vault = await Vault.connect(ownerSigner).deploy(
            feeRecipient,
            factory.address,
            referralManager.address,
            eventTracker.address,
            bexPriceDecoder.address,
            bexLiquidityManager.address
        );*/

        // Deploy Exponential Vault
        const ExpVault = await ethers.getContractFactory("BuzzVaultExponential");
        expVault = await ExpVault.connect(ownerSigner).deploy(
            feeRecipient,
            factory.address,
            referralManager.address,
            bexPriceDecoder.address,
            bexLiquidityManager.address
        );

        // Admin: Set Vault in the ReferralManager
        //await referralManager.connect(ownerSigner).setWhitelistedVault(vault.address, true);
        await referralManager.connect(ownerSigner).setWhitelistedVault(expVault.address, true);

        // Admin: Set Vault as the factory's vault & enable token creation
        //await factory.connect(ownerSigner).setVault(vault.address, true);
        await factory.connect(ownerSigner).setVault(expVault.address, true);

        await factory.connect(ownerSigner).setAllowTokenCreation(true);
    });
    describe("constructor", () => {
        it("should set the CREATE_DEPLOYER", async () => {
            expect(await factory.CREATE_DEPLOYER()).to.be.equal(create3Factory.address);
        });
        it("should grant the OWNER_ROLE to the owner", async () => {
            const ownerRoleHash = await factory.OWNER_ROLE();
            expect(await factory.hasRole(ownerRoleHash, ownerSigner.address)).to.be.equal(true);
        });
        it("should set the treasury", async () => {
            expect(await factory.treasury()).to.be.equal(feeRecipient);
        });
        it("should set the listingFee", async () => {
            expect(await factory.listingFee()).to.be.equal(listingFee);
        });
    });
    describe("createToken", () => {
        beforeEach(async () => {});
        it("should revert if token creation is disabled", async () => {
            await factory.setAllowTokenCreation(false);
            await expect(
                factory.createToken("TEST", "TEST", expVault.address, ethers.constants.AddressZero, formatBytes32String("12345"), ethers.utils.parseEther("0"), {
                    value: listingFee,
                })
            ).to.be.revertedWithCustomError(factory, "BuzzToken_TokenCreationDisabled");
        });
        it("should revert if the vault is not previously whitelisted", async () => {
            await expect(
                factory.createToken("TEST", "TEST", user1Signer.address, ethers.constants.AddressZero, formatBytes32String("12345"), ethers.utils.parseEther("0"), {
                    value: listingFee,
                })
            ).to.be.revertedWithCustomError(factory, "BuzzToken_VaultNotRegistered");
        });
        it("should revert if the listing fee is not sent", async () => {
            await expect(
                factory.createToken("TEST", "TEST", expVault.address, ethers.constants.AddressZero, formatBytes32String("12345"), ethers.utils.parseEther("0"), {
                    value: 0,
                })
            ).to.be.revertedWithCustomError(factory, "BuzzToken_InsufficientFee");
        });
        it("should revert if the max tax for the token is exceeded", async () => {
            await expect(
                factory.createToken("TEST", "TEST", expVault.address, user1Signer.address, formatBytes32String("12345"), ethers.utils.parseEther("10000"), {
                    value: listingFee,
                })
            ).to.be.revertedWithCustomError(factory, "BuzzToken_TaxTooHigh");
        });
        it("should revert on taxTo not being addr 0 but tax gt 0", async () => {
            await expect(
                factory.createToken("TEST", "TEST", expVault.address, user1Signer.address, formatBytes32String("12345"), ethers.utils.parseEther("0"), {
                    value: listingFee,
                })
            ).to.be.revertedWithCustomError(factory, "BuzzToken_TaxMismatch");
        });
        it("should revert on taxTo being addr 0 but tax == 0", async () => {
            await expect(
                factory.createToken("TEST", "TEST", expVault.address, ethers.constants.AddressZero, formatBytes32String("12345"), BigNumber.from(1000), {
                    value: listingFee,
                })
            ).to.be.revertedWithCustomError(factory, "BuzzToken_TaxMismatch");
        });
        it("should emit a TokenCreated event", async () => {
            const name = "TEST";
            const symbol = "TST";
            const tx = await factory.createToken(name, symbol, expVault.address, ethers.constants.AddressZero, formatBytes32String("12345"), ethers.utils.parseEther("0"), {
                value: listingFee,
            });
            const receipt = await tx.wait();
            const tokenCreatedEvent = receipt.events?.find((x: any) => x.event === "TokenCreated");
            expect(tokenCreatedEvent.args.name).to.be.equal(name);
            expect(tokenCreatedEvent.args.symbol).to.be.equal(symbol);
            expect(tokenCreatedEvent.args.deployer).to.be.equal(ownerSigner.address);
            expect(tokenCreatedEvent.args.vault).to.be.equal(expVault.address);

            // Get token contract
            token = await ethers.getContractAt("BuzzToken", tokenCreatedEvent?.args?.token);
            expect(await token.name()).to.be.equal(name);
        });
        describe("_deployToken", () => {
            beforeEach(async () => {
                treasuryBalanceBefore = await ethers.provider.getBalance(feeRecipient);
                const tx = await factory.createToken(
                    "TEST",
                    "TEST",
                    expVault.address,
                    ethers.constants.AddressZero,
                    formatBytes32String("123457"),
                    ethers.utils.parseEther("0"),
                    {
                        value: listingFee,
                    }
                );
                const receipt = await tx.wait();
                const tokenCreatedEvent = receipt.events?.find((x: any) => x.event === "TokenCreated");
                // Get token contract
                token = await ethers.getContractAt("BuzzToken", tokenCreatedEvent?.args?.token);
            });
            it("should create a token with the correct metadata", async () => {
                expect(await token.name()).to.be.equal("TEST");
                expect(await token.symbol()).to.be.equal("TEST");
            });
            it("should create a token with the storred contract supply", async () => {
                const totalSupply = await factory.INITIAL_SUPPLY();
                expect(await token.totalSupply()).to.be.equal(totalSupply);
            });
            it("should set the contract as deployed", async () => {
                expect(await factory.isDeployed(token.address)).to.be.equal(true);
            });
            it("should transfer the totalSupply to the vault", async () => {
                expect(await token.balanceOf(expVault.address)).to.be.equal(await token.totalSupply());
            });
            it("should transfer the listingFee to the treasury", async () => {
                expect(await ethers.provider.getBalance(feeRecipient)).to.be.equal(treasuryBalanceBefore.add(listingFee));
            });
        });
        describe("buy on deployment", () => {
            beforeEach(async () => {
                const listingFeeAndBuyAmount = listingFee.add(ethers.utils.parseEther("0.01"));
                const tax = BigNumber.from(1000);
                const tx = await factory.createToken(
                    "TEST",
                    "TEST",
                    expVault.address,
                    user2Signer.address,
                    formatBytes32String("123456"),
                    tax,
                    {
                        value: listingFeeAndBuyAmount,
                    }
                );
                const receipt = await tx.wait();
                const tokenCreatedEvent = receipt.events?.find((x: any) => x.event === "TokenCreated");
                // Get token contract
                token = await ethers.getContractAt("BuzzToken", tokenCreatedEvent?.args?.token);
            });
            it("should buy tokens and send them to the user", async () => {
                expect(await token.balanceOf(factory.address)).to.be.equal(0);
                expect(await token.balanceOf(ownerSigner.address)).to.be.gt(0);
            });
            it("should give the tax address tax gt 0", async () => {
                expect(await token.balanceOf(user2Signer.address)).to.be.gt(0);
            });
            it("should set the tax to the correct value", async () => {
                const tax = BigNumber.from(1000);
                expect(await token.TAX()).to.be.equal(tax);
            });
            it("should revert if the initial buy is bigger than 5% of the total supply", async () => {
                await expect(
                    factory.createToken(
                        "TEST",
                        "TEST",
                        expVault.address,
                        ethers.constants.AddressZero,
                        formatBytes32String("123456006"),
                        BigNumber.from(0),
                        {
                            value: ethers.utils.parseEther("100"),
                        }
                    )
                ).to.be.revertedWithCustomError(factory, "BuzzToken_MaxInitialBuyExceeded");
            });
        });
    });
    describe("setVault", () => {
        it("should revert if the vault address is the zero address", async () => {
            await expect(factory.connect(ownerSigner).setVault(ethers.constants.AddressZero, true)).to.be.revertedWithCustomError(
                factory,
                "BuzzToken_AddressZero"
            );
        });
        it("should revert if the vault is configured with the same bool", async () => {
            expect(await factory.vaults(expVault.address)).to.be.equal(true);
            await expect(factory.connect(ownerSigner).setVault(expVault.address, true)).to.be.revertedWithCustomError(factory, "BuzzToken_SameBool");
        });
        it("should set the vault", async () => {
            await factory.connect(ownerSigner).setVault(expVault.address, false);
            await factory.connect(ownerSigner).setVault(expVault.address, true);
            expect(await factory.vaults(expVault.address)).to.be.equal(true);
        });
        it("should emit a VaultSet event", async () => {
            await factory.connect(ownerSigner).setVault(expVault.address, false);

            await expect(factory.connect(ownerSigner).setVault(expVault.address, true)).to.emit(factory, "VaultSet").withArgs(expVault.address, true);
        });
        it("should revert if the caller doesn't have an owner role", async () => {
            await expect(factory.connect(user1Signer).setVault(expVault.address, true)).to.be.reverted;
        });
    });
    describe("setAllowTokenCreation", () => {
        it("should revert if the caller doesn't have an owner role", async () => {
            await expect(factory.connect(user1Signer).setAllowTokenCreation(true)).to.be.reverted;
        });
        it("should revert if it has the same bool", async () => {
            expect(await factory.allowTokenCreation()).to.be.equal(true);
            await expect(factory.connect(ownerSigner).setAllowTokenCreation(true)).to.be.revertedWithCustomError(factory, "BuzzToken_SameBool");
        });
        it("should set the token creation status", async () => {
            expect(await factory.allowTokenCreation()).to.be.equal(true);
            await factory.connect(ownerSigner).setAllowTokenCreation(false);
            expect(await factory.allowTokenCreation()).to.be.equal(false);
        });
        it("should emit an AllowTokenCreation event", async () => {
            expect(await factory.allowTokenCreation()).to.be.equal(true);
            await expect(factory.connect(ownerSigner).setAllowTokenCreation(false)).to.emit(factory, "TokenCreationSet").withArgs(false);
        });
    });
    describe("setListingFee", () => {
        it("should revert if the caller doesn't have an owner role", async () => {
            await expect(factory.connect(user1Signer).setListingFee(ethers.utils.parseEther("0.003"))).to.be.reverted;
        });
        it("should set the listing fee", async () => {
            await factory.connect(ownerSigner).setListingFee(ethers.utils.parseEther("0.003"));
            expect(await factory.listingFee()).to.be.equal(ethers.utils.parseEther("0.003"));
        });
        it("should emit a ListingFeeSet event", async () => {
            expect(await factory.listingFee()).to.be.equal(listingFee);
            await expect(factory.connect(ownerSigner).setListingFee(ethers.utils.parseEther("0.003")))
                .to.emit(factory, "ListingFeeSet")
                .withArgs(ethers.utils.parseEther("0.003"));
        });
    });
    describe("setTreasury", () => {
        it("should revert if the caller doesn't have an owner role", async () => {
            await expect(factory.connect(user1Signer).setTreasury(user1Signer.address)).to.be.reverted;
        });
        it("should set the treasury", async () => {
            expect(await factory.treasury()).to.be.equal(feeRecipient);
            await factory.connect(ownerSigner).setTreasury(user1Signer.address);
            expect(await factory.treasury()).to.be.equal(user1Signer.address);
        });
        it("should emit a TreasurySet event", async () => {
            expect(await factory.treasury()).to.be.equal(feeRecipient);
            await expect(factory.connect(ownerSigner).setTreasury(user1Signer.address)).to.emit(factory, "TreasurySet").withArgs(user1Signer.address);
        });
    });
});
