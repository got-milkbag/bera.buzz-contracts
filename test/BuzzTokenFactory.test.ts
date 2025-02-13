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
    let treasury: SignerWithAddress;
    let factory: Contract;
    let token: Contract;
    let referralManager: Contract;
    let expVault: Contract;
    let create3Factory: Contract;
    let bexLiquidityManager: Contract;
    let treasuryBalanceBefore: BigNumber;
    let feeManager: Contract;
    let wBera: Contract;
    let tokenCreatedEvent: any;

    const highlightsSuffix = ethers.utils.arrayify("0x");
    const directRefFeeBps = 1500; // 15% of protocol fee
    const indirectRefFeeBps = 100; // fixed 1%
    const listingFee = ethers.utils.parseEther("0.002");
    const payoutThreshold = 0;
    const bexWeightedPoolFactory = "0x09836Ff4aa44C9b8ddD2f85683aC6846E139fFBf";
    const bexVault = "0x9C8a5c82e797e074Fe3f121B326b140CEC4bcb33";
    let validUntil: number;

    beforeEach(async () => {
        validUntil = (await helpers.time.latest()) + ONE_YEAR_IN_SECS;

        [ownerSigner, user1Signer, treasury] = await ethers.getSigners();

        // Deploy mock create3factory
        const Create3Factory = await ethers.getContractFactory("CREATE3FactoryMock");
        create3Factory = await Create3Factory.connect(ownerSigner).deploy();

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
        factory = await Factory.connect(ownerSigner).deploy(ownerSigner.address, create3Factory.address, feeManager.address, highlightsSuffix);

        // Deploy liquidity manager
        const BexLiquidityManager = await ethers.getContractFactory("BexLiquidityManager");
        bexLiquidityManager = await BexLiquidityManager.connect(ownerSigner).deploy(bexWeightedPoolFactory, bexVault);
        await bexLiquidityManager.connect(ownerSigner).addVaults([ownerSigner.address]);

        // Deploy Linear Vault
        /*const Vault = await ethers.getContractFactory("BuzzVaultLinear");
        vault = await Vault.connect(ownerSigner).deploy(
            feeRecipient,
            factory.address,
            referralManager.address,
            eventTracker.address,
            bexLiquidityManager.address
        );*/

        // Deploy Exponential Vault
        const ExpVault = await ethers.getContractFactory("BuzzVaultExponential");
        expVault = await ExpVault.connect(ownerSigner).deploy(
            feeManager.address,
            factory.address,
            referralManager.address,
            bexLiquidityManager.address,
            wBera.address
        );

        // Admin: Set Vault in the ReferralManager
        //await referralManager.connect(ownerSigner).setWhitelistedVault(vault.address, true);
        await referralManager.connect(ownerSigner).setWhitelistedVault(expVault.address, true);

        // Admin: Whitelist base token in Factory
        await factory.connect(ownerSigner).setAllowedBaseToken(wBera.address, ethers.utils.parseEther("0.01"), ethers.utils.parseEther("100"), true);

        // Admin: Set Vault as the factory's vault & enable token creation
        //await factory.connect(ownerSigner).setVault(vault.address, true);
        await factory.connect(ownerSigner).setVault(expVault.address, true);

        await factory.connect(ownerSigner).setAllowTokenCreation(true);

        // Get some wBera
        await wBera.connect(ownerSigner).deposit({value: ethers.utils.parseEther("10")});
    });
    describe("constructor", () => {
        it("should set the createDeployer", async () => {
            expect(await factory.CREATE_DEPLOYER()).to.be.equal(create3Factory.address);
        });
        it("should grant the ownerRole to the owner", async () => {
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
                    [wBera.address, expVault.address],
                    [ethers.utils.parseEther("1"), ethers.utils.parseEther("1000")],
                    0,
                    formatBytes32String("12345"),
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
                    [wBera.address, user1Signer.address],
                    [ethers.utils.parseEther("1"), ethers.utils.parseEther("1000")],
                    0,
                    formatBytes32String("12345"),
                    {
                        value: listingFee,
                    }
                )
            ).to.be.revertedWithCustomError(factory, "BuzzToken_VaultNotRegistered");
        });
        it("should revert if the base token address is the zero address", async () => {
            await expect(
                factory.createToken(
                    ["TEST", "TST"],
                    [ethers.constants.AddressZero, ethers.constants.AddressZero],
                    [ethers.utils.parseEther("1"), ethers.utils.parseEther("1000")],
                    0,
                    formatBytes32String("12345"),
                    {
                        value: listingFee,
                    }
                )
            ).to.be.revertedWithCustomError(factory, "BuzzToken_AddressZero");
         });
        it("should revert if the listing fee is less than required", async () => {
            await expect(
                factory.createToken(
                    ["TEST", "TST"],
                    [wBera.address, expVault.address],
                    [ethers.utils.parseEther("1"), ethers.utils.parseEther("1000")],
                    0,
                    formatBytes32String("12345"),
                    {
                        value: listingFee.sub(1),
                    }
                )
            ).to.be.revertedWithCustomError(factory, "BuzzToken_InsufficientFee");
        });
        it("should revert if the base token is not enabled", async () => {
            await factory.setAllowedBaseToken(wBera.address, 0, 0, false);
            await expect(
                factory.createToken(
                    ["TEST", "TST"],
                    [wBera.address, expVault.address],
                    [ethers.utils.parseEther("1"), ethers.utils.parseEther("1000")],
                    0,
                    formatBytes32String("12345"),
                    {
                        value: listingFee,
                    }
                )
            ).to.be.revertedWithCustomError(factory, "BuzzToken_BaseTokenNotWhitelisted");
        });
        it("should revert if the initial reserves are not enough on token creation", async () => {
            await factory.setAllowedBaseToken(wBera.address, ethers.utils.parseEther("1000"), ethers.utils.parseEther("10000"), true);
            await expect(
                factory.createToken(
                    ["TEST", "TST"],
                    [wBera.address, expVault.address],
                    [ethers.utils.parseEther("1"), ethers.utils.parseEther("1000")],
                    0,
                    formatBytes32String("12345"),
                    {
                        value: listingFee,
                    }
                )
            ).to.be.revertedWithCustomError(factory, "BuzzToken_InvalidInitialReserves");
        });
        it("should revert if the final reserves are not enough on token creation", async () => {
            await factory.setAllowedBaseToken(wBera.address, ethers.utils.parseEther("0.1"), ethers.utils.parseEther("10000"), true);
            await expect(
                factory.createToken(
                    ["TEST", "TST"],
                    [wBera.address, expVault.address],
                    [ethers.utils.parseEther("1"), ethers.utils.parseEther("1000")],
                    0,
                    formatBytes32String("12345"),
                    {
                        value: listingFee,
                    }
                )
            ).to.be.revertedWithCustomError(factory, "BuzzToken_InvalidFinalReserves");
        });
        it("should revert if the token name is empty", async () => {
            await expect(
                factory.createToken(
                    ["", "TST"],
                    [wBera.address, expVault.address],
                    [ethers.utils.parseEther("1"), ethers.utils.parseEther("1000")],
                    0,
                    formatBytes32String("12345"),
                    {
                        value: listingFee,
                    }
                )
            ).to.be.revertedWithCustomError(factory, "BuzzToken_EmptyTokenName");
        });
        it("should revert if the token symbol is empty", async () => {
            await expect(
                factory.createToken(
                    ["TEST", ""],
                    [wBera.address, expVault.address],
                    [ethers.utils.parseEther("1"), ethers.utils.parseEther("1000")],
                    0,
                    formatBytes32String("12345"),
                    {
                        value: listingFee,
                    }
                )
            ).to.be.revertedWithCustomError(factory, "BuzzToken_EmptyTokenSymbol");
        });
        it("should revert if the token name is too long", async () => {
            await expect(
                factory.createToken(
                    ["aaaaaaaaaaaaaaaaa", "TST"],
                    [wBera.address, expVault.address],
                    [ethers.utils.parseEther("1"), ethers.utils.parseEther("1000")],
                    0,
                    formatBytes32String("12345"),
                    {
                        value: listingFee,
                    }
                )
            ).to.be.revertedWithCustomError(factory, "BuzzToken_TokenNameTooLong");
        });
        it("should revert if the token symbol is too long", async () => {
            await expect(
                factory.createToken(
                    ["TEST", "aaaaaaaaaaa"],
                    [wBera.address, expVault.address],
                    [ethers.utils.parseEther("1"), ethers.utils.parseEther("1000")],
                    0,
                    formatBytes32String("12345"),
                    {
                        value: listingFee,
                    }
                )
            ).to.be.revertedWithCustomError(factory, "BuzzToken_TokenSymbolTooLong");
        });
        it("should revert if the salt does not correspond to an address with the correct suffix", async () => {
            const salt = formatBytes32String("12345");
            const suffix = ethers.utils.arrayify("0x1bee");
            // Deploy factory
            const Factory = await ethers.getContractFactory("BuzzTokenFactory");
            const newFactory = await Factory.connect(ownerSigner).deploy(ownerSigner.address, create3Factory.address, feeManager.address, suffix);

            // Admin: Whitelist base token in Factory
            await newFactory.connect(ownerSigner).setAllowedBaseToken(wBera.address, ethers.utils.parseEther("0.01"), ethers.utils.parseEther("100"), true);
            // Admin: Set Vault as the factory's vault & enable token creation
            await newFactory.connect(ownerSigner).setVault(expVault.address, true);
            await newFactory.connect(ownerSigner).setAllowTokenCreation(true);

            await expect(
                newFactory.createToken(
                    ["TEST", "TST"],
                    [wBera.address, expVault.address],
                    [ethers.utils.parseEther("1"), ethers.utils.parseEther("1000")],
                    0,
                    salt,
                    {
                        value: listingFee,
                    }
                )
            ).to.be.revertedWithCustomError(newFactory, "BuzzTokenFactory_InvalidSuffix");
        });
        it("should emit a TokenCreated event", async () => {
            const name = "TEST";
            const symbol = "TST";
            const tx = await factory.createToken(
                [name, symbol],
                [wBera.address, expVault.address],
                [ethers.utils.parseEther("1"), ethers.utils.parseEther("1000")],
                0,
                formatBytes32String("12345"),
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

            // Get token contract
            token = await ethers.getContractAt("BuzzToken", tokenCreatedEvent?.args?.token);
            expect(await token.name()).to.be.equal(name);
            expect(await factory.isDeployed(token.address)).to.be.equal(true);
        });
        it("should emit a TokenRegistered event", async () => {
            const tx = expect(await factory.createToken(
                ["TEST", "TST"],
                [wBera.address, expVault.address],
                [ethers.utils.parseEther("1"), ethers.utils.parseEther("1000")],
                0,
                formatBytes32String("12345"),
                {
                    value: listingFee,
                }
            )).to.emit(expVault, "TokenRegistered").withArgs(
                token.address,
                wBera.address,
                ethers.utils.parseEther("1000000000"),
                ethers.utils.parseEther("1"),
                ethers.utils.parseEther("1000"),
                anyValue
            );
        });
        it("should refund the user for excess msg.sender", async () => {
            const listingFeeAndBuyAmount = listingFee.add(ethers.utils.parseEther("1"));
            const balanceBefore = await ethers.provider.getBalance(ownerSigner.address);
            const tx = await factory.createToken(
                ["TEST", "TST"],
                [wBera.address, expVault.address],
                [ethers.utils.parseEther("1"), ethers.utils.parseEther("1000")],
                0,
                formatBytes32String("12345"),
                {
                    value: listingFeeAndBuyAmount,
                }
            );
            const receipt = await tx.wait();
            const balanceAfter = await ethers.provider.getBalance(ownerSigner.address);
            const gasUsed = receipt.cumulativeGasUsed.mul(receipt.effectiveGasPrice);
            expect(balanceAfter.add(gasUsed)).to.be.eq(balanceBefore.sub(listingFee));
        });
        describe("_deployToken", () => {
            beforeEach(async () => {
                treasuryBalanceBefore = await ethers.provider.getBalance(treasury.address);
                const tx = await factory.createToken(
                    ["TEST", "TST"],
                    [wBera.address, expVault.address],
                    [ethers.utils.parseEther("1"), ethers.utils.parseEther("1000")],
                    0,
                    formatBytes32String("123457"),
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

                const tx = await factory.createToken(
                    ["TEST", "TST"],
                    [wBera.address, expVault.address],
                    [ethers.utils.parseEther("1"), ethers.utils.parseEther("1000")],
                    ethers.utils.parseEther("0.01"),
                    formatBytes32String("12345"),
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
        });
        describe("buy on deployment - native currency", () => {
            beforeEach(async () => {});
            it("should revert if the remaining value is not the same as the baseAmount", async () => {
                // Deploy and buy token
                const listingFeeAndBuyAmount = listingFee.add(ethers.utils.parseEther("0.01"));

                await expect(
                    factory.createToken(
                        ["TEST", "TST"],
                        [wBera.address, expVault.address],
                        [ethers.utils.parseEther("1"), ethers.utils.parseEther("1000")],
                        ethers.utils.parseEther("0.02"),
                        formatBytes32String("12345"),
                        {
                            value: listingFeeAndBuyAmount,
                        }
                    )
                ).to.be.revertedWithCustomError(factory, "BuzzToken_BaseAmountNotEnough");
            });
            it("should purchase the remaining value passed and emit", async () => {
                // Deploy and buy token
                const listingFeeAndBuyAmount = listingFee.add(ethers.utils.parseEther("0.01"));

                expect(
                    await factory.createToken(
                        ["TEST", "TST"],
                        [wBera.address, expVault.address],
                        [ethers.utils.parseEther("1"), ethers.utils.parseEther("1000")],
                        ethers.utils.parseEther("0.01"),
                        formatBytes32String("12345"),
                        {
                            value: listingFeeAndBuyAmount,
                        }
                    )
                )
                    .to.emit(expVault, "Trade")
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
                await wBera.approve(factory.address, ethers.utils.parseEther("0.1"));
                expect(
                    await factory.createToken(
                        ["TEST", "TST"],
                        [wBera.address, expVault.address],
                        [ethers.utils.parseEther("1"), ethers.utils.parseEther("1000")],
                        ethers.utils.parseEther("0.1"),
                        formatBytes32String("12345"),
                        {
                            value: listingFee,
                        }
                    )
                )
                    .to.emit(expVault, "Trade")
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
            await expect(factory.connect(user1Signer).setVault(expVault.address, true)).to.be.revertedWith('AccessControl: account 0x70997970c51812dc3a010c7d01b50e0d17dc79c8 is missing role 0xb19546dff01e856fb3f010c267a7b1c60363cf8a4664e21cc89c26224620214e');
        });
    });
    describe("setAllowTokenCreation", () => {
        it("should revert if the caller doesn't have an owner role", async () => {
            await expect(factory.connect(user1Signer).setAllowTokenCreation(true)).to.be.revertedWith('AccessControl: account 0x70997970c51812dc3a010c7d01b50e0d17dc79c8 is missing role 0xb19546dff01e856fb3f010c267a7b1c60363cf8a4664e21cc89c26224620214e');
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
            await expect(factory.connect(user1Signer).setFeeManager(user1Signer.address)).to.be.revertedWith('AccessControl: account 0x70997970c51812dc3a010c7d01b50e0d17dc79c8 is missing role 0xb19546dff01e856fb3f010c267a7b1c60363cf8a4664e21cc89c26224620214e');
        });
        it("should revert if the feeManager address is the zero address", async () => {
            await expect(factory.connect(ownerSigner).setFeeManager(ethers.constants.AddressZero)).to.be.revertedWithCustomError(factory, "BuzzToken_AddressZero");
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
    describe("setAllowedBaseToken", () => {
        it("should revert if the caller doesn't have an owner role", async () => {
            await expect(factory.connect(user1Signer).setAllowedBaseToken(wBera.address, ethers.utils.parseEther("1"), ethers.utils.parseEther("1000"), true)).to.be.revertedWith('AccessControl: account 0x70997970c51812dc3a010c7d01b50e0d17dc79c8 is missing role 0xb19546dff01e856fb3f010c267a7b1c60363cf8a4664e21cc89c26224620214e');
        });
        it("should revert if the base token address is the zero address", async () => {
            await expect(factory.connect(ownerSigner).setAllowedBaseToken(ethers.constants.AddressZero, ethers.utils.parseEther("1"), ethers.utils.parseEther("1000"), true)).to.be.revertedWithCustomError(factory, "BuzzToken_AddressZero");
        });
        it("should set the base token status", async () => {
            expect(await factory.whitelistedBaseTokens(wBera.address)).to.be.equal(true);
            await factory.connect(ownerSigner).setAllowedBaseToken(wBera.address, ethers.utils.parseEther("1"), ethers.utils.parseEther("1000"), false);
            expect(await factory.whitelistedBaseTokens(wBera.address)).to.be.equal(false);
        });
        it("should emit an AllowedBaseToken event", async () => {
            expect(await factory.whitelistedBaseTokens(wBera.address)).to.be.equal(true);
            await expect(factory.connect(ownerSigner).setAllowedBaseToken(wBera.address, ethers.utils.parseEther("1"), ethers.utils.parseEther("1000"), false))
                .to.emit(factory, "BaseTokenWhitelisted")
                .withArgs(
                    wBera.address, 
                    ethers.utils.parseEther("1"),
                    ethers.utils.parseEther("1000"),
                    false
                );
        });
    });
});
