import {expect} from "chai";
import {ethers} from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import * as helpers from "@nomicfoundation/hardhat-network-helpers";
import {BigNumber, Contract} from "ethers";
import {formatBytes32String} from "ethers/lib/utils";
import {anyValue} from "@nomicfoundation/hardhat-chai-matchers/withArgs";

describe("BuzzTokenFactory Tests", () => {
    const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;

    let ownerSigner: SignerWithAddress;
    let user1Signer: SignerWithAddress;
    let user2Signer: SignerWithAddress;
    let treasury: SignerWithAddress;
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
    let feeManager: Contract;
    let wBera: Contract;
    let tokenCreatedEvent: any;

    const directRefFeeBps = 1500; // 15% of protocol fee
    const indirectRefFeeBps = 100; // fixed 1%
    const listingFee = ethers.utils.parseEther("0.002");
    const payoutThreshold = 0;
    const crocSwapDexAddress = "0xAB827b1Cc3535A9e549EE387A6E9C3F02F481B49";
    let validUntil: number;

    beforeEach(async () => {
        validUntil = (await helpers.time.latest()) + ONE_YEAR_IN_SECS;

        [ownerSigner, user1Signer, user2Signer, treasury] = await ethers.getSigners();

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

        //Deploy WBera Mock
        const WBera = await ethers.getContractFactory("WBERA");
        wBera = await WBera.connect(ownerSigner).deploy();

        // Deploy FeeManager
        const FeeManager = await ethers.getContractFactory("FeeManager");
        feeManager = await FeeManager.connect(ownerSigner).deploy(treasury.address, 100, listingFee, 420);

        // Deploy ReferralManager
        const ReferralManager = await ethers.getContractFactory("ReferralManager");
        referralManager = await ReferralManager.connect(ownerSigner).deploy(
            directRefFeeBps,
            indirectRefFeeBps,
            validUntil,
            [wBera.address],
            [payoutThreshold]
        );

        // Deploy factory
        const Factory = await ethers.getContractFactory("BuzzTokenFactory");
        factory = await Factory.connect(ownerSigner).deploy(ownerSigner.address, create3Factory.address, feeManager.address);

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
            feeManager.address,
            factory.address,
            referralManager.address,
            bexPriceDecoder.address,
            bexLiquidityManager.address,
            wBera.address
        );

        // Admin: Set Vault in the ReferralManager
        //await referralManager.connect(ownerSigner).setWhitelistedVault(vault.address, true);
        await referralManager.connect(ownerSigner).setWhitelistedVault(expVault.address, true);

        // Admin: Set Vault as the factory's vault & enable token creation
        //await factory.connect(ownerSigner).setVault(vault.address, true);
        await factory.connect(ownerSigner).setVault(expVault.address, true);

        await factory.connect(ownerSigner).setAllowTokenCreation(true);

        // Get some wBera
        await wBera.connect(ownerSigner).deposit({value: ethers.utils.parseEther("10")});
    });
    describe("constructor", () => {
        it("should set the CREATE_DEPLOYER", async () => {
            expect(await factory.CREATE_DEPLOYER()).to.be.equal(create3Factory.address);
        });
        it("should grant the OWNER_ROLE to the owner", async () => {
            const ownerRoleHash = await factory.OWNER_ROLE();
            expect(await factory.hasRole(ownerRoleHash, ownerSigner.address)).to.be.equal(true);
        });
        it("should set the feeManager", async () => {
            expect(await factory.feeManager()).to.be.equal(feeManager.address);
        });
    });
    describe("createToken", () => {
        beforeEach(async () => {});
        it("should revert if token creation is disabled", async () => {
            await factory.setAllowTokenCreation(false);
            await expect(
                factory.createToken(
                    ["TEST", "TST"],
                    [wBera.address, expVault.address, ethers.constants.AddressZero],
                    0,
                    formatBytes32String("12345"),
                    ethers.utils.parseEther("0"),
                    ethers.utils.parseEther("69420"),
                    {
                        value: listingFee,
                    }
                )
            ).to.be.revertedWithCustomError(factory, "BuzzToken_TokenCreationDisabled");
        });
        it("should revert if the vault is not previously whitelisted", async () => {
            await expect(
                factory.createToken(
                    ["TEST", "TST"],
                    [wBera.address, user1Signer.address, ethers.constants.AddressZero],
                    0,
                    formatBytes32String("12345"),
                    ethers.utils.parseEther("0"),
                    ethers.utils.parseEther("69420"),
                    {
                        value: listingFee,
                    }
                )
            ).to.be.revertedWithCustomError(factory, "BuzzToken_VaultNotRegistered");
        });
        // it("should revert if the base token address is the zero address", async () => {
        //     await expect(
        //         factory.createToken(
        //             ["TEST", "TST"],
        //             [ethers.constants.AddressZero, user1Signer.address, ethers.constants.AddressZero],
        //             0,
        //             formatBytes32String("12345"),
        //             ethers.utils.parseEther("0"),
        //             {
        //                 value: listingFee,
        //             }
        //         )
        //     ).to.be.revertedWithCustomError(factory, "BuzzToken_AddressZero");
        // });
        it("should revert if the listing fee is less than required", async () => {
            await expect(
                factory.createToken(
                    ["TEST", "TST"],
                    [wBera.address, expVault.address, ethers.constants.AddressZero],
                    0,
                    formatBytes32String("12345"),
                    ethers.utils.parseEther("0"),
                    ethers.utils.parseEther("69420"),
                    {
                        value: listingFee.sub(1),
                    }
                )
            ).to.be.revertedWithCustomError(factory, "BuzzToken_InsufficientFee");
        });
        it("should revert if the max tax for the token is exceeded", async () => {
            await expect(
                factory.createToken(
                    ["TEST", "TST"],
                    [wBera.address, expVault.address, user1Signer.address],
                    0,
                    formatBytes32String("12345"),
                    ethers.utils.parseEther("10000"),
                    ethers.utils.parseEther("69420"),
                    {
                        value: listingFee,
                    }
                )
            ).to.be.revertedWithCustomError(factory, "BuzzToken_TaxTooHigh");
        });
        it("should revert on taxTo not being addr 0 but tax gt 0", async () => {
            await expect(
                factory.createToken(
                    ["TEST", "TST"],
                    [wBera.address, expVault.address, user1Signer.address],
                    0,
                    formatBytes32String("12345"),
                    ethers.utils.parseEther("0"),
                    ethers.utils.parseEther("69420"),
                    {
                        value: listingFee,
                    }
                )
            ).to.be.revertedWithCustomError(factory, "BuzzToken_TaxMismatch");
        });
        it("should revert on taxTo being addr 0 but tax == 0", async () => {
            await expect(
                factory.createToken(
                    ["TEST", "TST"],
                    [wBera.address, expVault.address, ethers.constants.AddressZero],
                    0,
                    formatBytes32String("12345"),
                    BigNumber.from(1000),
                    ethers.utils.parseEther("69420"),
                    {
                        value: listingFee,
                    }
                )
            ).to.be.revertedWithCustomError(factory, "BuzzToken_TaxMismatch");
        });
        it("should revert if the market cap is under the minimum", async () => {
            await expect(
                factory.createToken(
                    ["TEST", "TST"],
                    [wBera.address, expVault.address, ethers.constants.AddressZero],
                    0,
                    formatBytes32String("12345"),
                    0,
                    0,
                    {
                        value: listingFee,
                    }
                )
            ).to.be.revertedWithCustomError(factory, "BuzzToken_MarketCapUnderMin");
        });
        it("should emit a TokenCreated event", async () => {
            const name = "TEST";
            const symbol = "TST";
            const tx = await factory.createToken(
                [name, symbol],
                [wBera.address, expVault.address, user2Signer.address],
                0,
                formatBytes32String("12345"),
                BigNumber.from(1000),
                ethers.utils.parseEther("69420"),
                {
                    value: listingFee,
                }
            );
            const receipt = await tx.wait();
            const tokenCreatedEvent = receipt.events?.find((x: any) => x.event === "TokenCreated");
            expect(tokenCreatedEvent.args.name).to.be.equal(name);
            expect(tokenCreatedEvent.args.symbol).to.be.equal(symbol);
            expect(tokenCreatedEvent.args.baseToken).to.be.equal(wBera.address);
            expect(tokenCreatedEvent.args.deployer).to.be.equal(ownerSigner.address);
            expect(tokenCreatedEvent.args.vault).to.be.equal(expVault.address);
            expect(tokenCreatedEvent.args.tax).to.be.equal(BigNumber.from(1000));
            expect(tokenCreatedEvent.args.taxTo).to.be.equal(user2Signer.address);

            // Get token contract
            token = await ethers.getContractAt("BuzzToken", tokenCreatedEvent?.args?.token);
            expect(await token.name()).to.be.equal(name);
        });
        describe("_deployToken", () => {
            beforeEach(async () => {
                treasuryBalanceBefore = await ethers.provider.getBalance(treasury.address);
                const tx = await factory.createToken(
                    ["TEST", "TST"],
                    [wBera.address, expVault.address, ethers.constants.AddressZero],
                    0,
                    formatBytes32String("123457"),
                    ethers.utils.parseEther("0"),
                    ethers.utils.parseEther("69420"),
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
                expect(await token.symbol()).to.be.equal("TST");
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
                expect(await ethers.provider.getBalance(treasury.address)).to.be.equal(treasuryBalanceBefore.add(listingFee));
            });
        });
        describe("buy on deployment", () => {
            beforeEach(async () => {
                const listingFeeAndBuyAmount = listingFee.add(ethers.utils.parseEther("0.01"));
                const tax = BigNumber.from(1000);

                const tx = await factory.createToken(
                    ["TEST", "TST"],
                    [wBera.address, expVault.address, user2Signer.address],
                    ethers.utils.parseEther("0.01"),
                    formatBytes32String("12345"),
                    tax,
                    ethers.utils.parseEther("69420"),
                    {
                        value: listingFeeAndBuyAmount,
                    }
                );
                const receipt = await tx.wait();
                tokenCreatedEvent = receipt.events?.find((x: any) => x.event === "TokenCreated");
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
                const listingFeeAndBuyAmount = listingFee.add(ethers.utils.parseEther("100"));
                await expect(
                    factory.createToken(
                        ["TEST", "TST"],
                        [wBera.address, expVault.address, ethers.constants.AddressZero],
                        ethers.utils.parseEther("100"),
                        formatBytes32String("123456006"),
                        BigNumber.from(0),
                        ethers.utils.parseEther("69420"),
                        {
                            value: listingFeeAndBuyAmount,
                        }
                    )
                ).to.be.revertedWithCustomError(factory, "BuzzToken_MaxInitialBuyExceeded");
            });
        });
        describe("buy on deployment - native currency", () => {
            beforeEach(async () => {});
            it("should revert if the remaining value is not the same as the baseAmount", async () => {
                // Deploy and buy token
                const listingFeeAndBuyAmount = listingFee.add(ethers.utils.parseEther("0.01"));
                const tax = BigNumber.from(1000);

                await expect(
                    factory.createToken(
                        ["TEST", "TST"],
                        [wBera.address, expVault.address, user2Signer.address],
                        ethers.utils.parseEther("0.02"),
                        formatBytes32String("12345"),
                        tax,
                        ethers.utils.parseEther("69420"),
                        {
                            value: listingFeeAndBuyAmount,
                        }
                    )
                ).to.be.revertedWithCustomError(factory, "BuzzToken_BaseAmountNotEnough");
            });
            it("should purchase the remaining value passed and emit", async () => {
                // Deploy and buy token
                const listingFeeAndBuyAmount = listingFee.add(ethers.utils.parseEther("0.01"));
                const tax = BigNumber.from(1000);

                expect(
                    await factory.createToken(
                        ["TEST", "TST"],
                        [wBera.address, expVault.address, user2Signer.address],
                        ethers.utils.parseEther("0.01"),
                        formatBytes32String("12345"),
                        tax,
                        ethers.utils.parseEther("69420"),
                        {
                            value: listingFeeAndBuyAmount,
                        }
                    )
                )
                    .to.emit(vault, "Trade")
                    .withArgs(
                        ownerSigner.address,
                        token.address,
                        wBera.address,
                        anyValue,
                        ethers.utils.parseEther("0.01"),
                        anyValue,
                        anyValue,
                        anyValue,
                        anyValue,
                        true
                    );
            });
        });
        describe("buy on deployment - base token", () => {
            beforeEach(async () => {});
            it("should purchase the using base tokens and emit a trade event", async () => {
                // Deploy and buy token
                const tax = BigNumber.from(1000);
                await wBera.approve(factory.address, ethers.utils.parseEther("0.1"));
                expect(
                    await factory.createToken(
                        ["TEST", "TST"],
                        [wBera.address, expVault.address, user2Signer.address],
                        ethers.utils.parseEther("0.1"),
                        formatBytes32String("12345"),
                        tax,
                        ethers.utils.parseEther("69420"),
                        {
                            value: listingFee,
                        }
                    )
                )
                    .to.emit(vault, "Trade")
                    .withArgs(
                        ownerSigner.address,
                        token.address,
                        wBera.address,
                        anyValue,
                        ethers.utils.parseEther("0.1"),
                        anyValue,
                        anyValue,
                        anyValue,
                        anyValue,
                        true
                    );
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
    describe("setFeeManager", () => {
        it("should revert if the caller doesn't have an owner role", async () => {
            await expect(factory.connect(user1Signer).setFeeManager(user1Signer.address)).to.be.reverted;
        });
        it("should set the feeManager", async () => {
            expect(await factory.feeManager()).to.be.equal(feeManager.address);
            await factory.connect(ownerSigner).setFeeManager(user1Signer.address);
            expect(await factory.feeManager()).to.be.equal(user1Signer.address);
        });
        it("should emit a FeeManagerSet event", async () => {
            expect(await factory.feeManager()).to.be.equal(feeManager.address);
            await expect(factory.connect(ownerSigner).setFeeManager(user1Signer.address))
                .to.emit(factory, "FeeManagerSet")
                .withArgs(user1Signer.address);
        });
    });
});
