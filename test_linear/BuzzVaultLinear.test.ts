import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import * as helpers from "@nomicfoundation/hardhat-network-helpers";
import { BigNumber, Contract } from "ethers";
import { formatBytes32String } from "ethers/lib/utils";

// Function to calculate the price per token in ETH
function calculateTokenPrice(etherSpent: BigNumber, tokensReceived: BigNumber) {
    // Calculate the price per token (ETH)
    const pricePerTokenBN = etherSpent.mul(ethers.BigNumber.from("10").pow(18)).div(tokensReceived);

    // Convert the result back to Ether format (as string with 18 decimals)
    const pricePerTokenInEther = ethers.utils.formatEther(pricePerTokenBN);

    return pricePerTokenInEther;
}

describe("BuzzVaultLinear Tests", () => {
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
    let eventTracker: Contract;
    let expVault: Contract;
    let bexLpToken: Contract;
    let crocQuery: Contract;
    let create3Factory: Contract;
    let bexLiquidityManager: Contract;

    const directRefFeeBps = 1500; // 15% of protocol fee
    const indirectRefFeeBps = 100; // fixed 1%
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

        //Deploy mock ICrocQuery
        const ICrocQuery = await ethers.getContractFactory("CrocQueryMock");
        crocQuery = await ICrocQuery.connect(ownerSigner).deploy(ethers.BigNumber.from("83238796252293901415"));

        // Deploy ReferralManager
        const ReferralManager = await ethers.getContractFactory("ReferralManager");
        referralManager = await ReferralManager.connect(ownerSigner).deploy(directRefFeeBps, indirectRefFeeBps, validUntil, payoutThreshold);

        // Deploy EventTracker
        const EventTracker = await ethers.getContractFactory("BuzzEventTracker");
        eventTracker = await EventTracker.connect(ownerSigner).deploy([]);

        // Deploy factory
        const Factory = await ethers.getContractFactory("BuzzTokenFactory");
        factory = await Factory.connect(ownerSigner).deploy(eventTracker.address, ownerSigner.address, create3Factory.address);

        // Deploy liquidity manager
        const BexLiquidityManager = await ethers.getContractFactory("BexLiquidityManager");
        bexLiquidityManager = await BexLiquidityManager.connect(ownerSigner).deploy(crocSwapDexAddress);

        // Deploy Linear Vault
        const Vault = await ethers.getContractFactory("BuzzVaultLinear");
        vault = await Vault.connect(ownerSigner).deploy(
            feeRecipient,
            factory.address,
            referralManager.address,
            eventTracker.address,
            bexLiquidityManager.address
        );

        // Deploy Exponential Vault
        const ExpVault = await ethers.getContractFactory("BuzzVaultExponential");
        expVault = await ExpVault.connect(ownerSigner).deploy(
            feeRecipient,
            factory.address,
            referralManager.address,
            eventTracker.address,
            bexLiquidityManager.address
        );

        // Admin: Set Vault in the ReferralManager
        await referralManager.connect(ownerSigner).setWhitelistedVault(vault.address, true);
        await referralManager.connect(ownerSigner).setWhitelistedVault(expVault.address, true);

        // Admin: Set event setter contracts in EventTracker
        await eventTracker.connect(ownerSigner).setEventSetter(vault.address, true);
        await eventTracker.connect(ownerSigner).setEventSetter(expVault.address, true);
        await eventTracker.connect(ownerSigner).setEventSetter(factory.address, true);

        // Admin: Set Vault as the factory's vault & enable token creation
        await factory.connect(ownerSigner).setVault(vault.address, true);
        await factory.connect(ownerSigner).setVault(expVault.address, true);

        await factory.connect(ownerSigner).setAllowTokenCreation(true);

        // Create a token
        const tx = await factory.createToken("TEST", "TEST", "Test token is the best", "0x0", vault.address, formatBytes32String("12345"));
        const receipt = await tx.wait();
        const tokenCreatedEvent = receipt.events?.find((x: any) => x.event === "TokenCreated");

        // Get token contract
        token = await ethers.getContractAt("BuzzToken", tokenCreatedEvent?.args?.token);
    });
    describe("constructor", () => {
        it("should set the factory address", async () => {
            expect(await vault.factory()).to.be.equal(factory.address);
        });
        it("should set the feeRecipient address", async () => {
            expect(await vault.feeRecipient()).to.be.equal(feeRecipient);
        });
        it("should set the referralManager address", async () => {
            expect(await vault.referralManager()).to.be.equal(referralManager.address);
        });
        it("should set the eventTracker address", async () => {
            expect(await vault.eventTracker()).to.be.equal(eventTracker.address);
        });
    });
    describe("registerToken", () => {
        beforeEach(async () => { });
        it("should register token transferring totalSupply", async () => {
            const tokenInfo = await vault.tokenInfo(token.address);
            expect(await token.balanceOf(vault.address)).to.be.equal(await token.totalSupply());
            //expect(tokenInfo.beraBalance).to.be.equal(0);
            expect(tokenInfo.bexListed).to.be.equal(false);

            //expect(tokenInfo.tokenBalance).to.be.equal(await token.balanceOf(vault.address));
        });
        it("should revert if caller is not factory", async () => {
            await expect(vault.connect(user1Signer).registerToken(factory.address, ethers.utils.parseEther("100"))).to.be.revertedWithCustomError(
                vault,
                "BuzzVault_Unauthorized"
            );
        });
    });
    describe("buy", () => {
        beforeEach(async () => { });
        it("should handle multiple buys in succession", async () => {
            const initialVaultTokenBalance = await token.balanceOf(vault.address);
            const initialUser1Balance = await ethers.provider.getBalance(user1Signer.address);
            const initialUser2Balance = await ethers.provider.getBalance(user2Signer.address);

            // Buy 1: user1 buys a small amount of tokens
            await vault
                .connect(user1Signer)
                .buy(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, { value: ethers.utils.parseEther("0.01") });
            const vaultTokenBalanceAfterFirstBuy = await token.balanceOf(vault.address);
            const user1BalanceAfterFirstBuy = await ethers.provider.getBalance(user1Signer.address);
            const tokenInfoAfterFirstBuy = await vault.tokenInfo(token.address);

            console.log("Token balance after first buy:", vaultTokenBalanceAfterFirstBuy.toString());
            console.log("User1 BERA balance after first buy:", user1BalanceAfterFirstBuy.toString());
            console.log("Vault token info after first buy:", tokenInfoAfterFirstBuy);

            expect(vaultTokenBalanceAfterFirstBuy).to.be.below(initialVaultTokenBalance);

            // Buy 2: user2 buys using same BERA amount
            await vault
                .connect(user2Signer)
                .buy(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, { value: ethers.utils.parseEther("0.01") });
            const vaultTokenBalanceAfterSecondBuy = await token.balanceOf(vault.address);
            const user2BalanceAfterSecondBuy = await ethers.provider.getBalance(user2Signer.address);
            const tokenInfoAfterSecondBuy = await vault.tokenInfo(token.address);

            console.log("Token balance after second buy:", vaultTokenBalanceAfterSecondBuy.toString());
            console.log("User2 BERA balance after second buy:", user2BalanceAfterSecondBuy.toString());
            console.log("Vault token info after second buy:", tokenInfoAfterSecondBuy);

            expect(vaultTokenBalanceAfterSecondBuy).to.be.below(vaultTokenBalanceAfterFirstBuy);

            // Assertions on balances, vault state, etc.
            expect(tokenInfoAfterSecondBuy.tokenBalance).to.be.below(tokenInfoAfterFirstBuy.tokenBalance);
            expect(tokenInfoAfterSecondBuy.beraBalance).to.be.above(tokenInfoAfterFirstBuy.beraBalance);
        });
        it("should revert if msg.value is zero", async () => {
            await expect(
                vault.buy(token.address, ethers.utils.parseEther("1"), ethers.constants.AddressZero, { value: 0 })
            ).to.be.revertedWithCustomError(vault, "BuzzVault_QuoteAmountZero");
        });
        it("should revert if token doesn't exist", async () => {
            await expect(
                vault.buy(ownerSigner.address, ethers.utils.parseEther("1"), ethers.constants.AddressZero, { value: ethers.utils.parseEther("0.1") })
            ).to.be.revertedWithCustomError(vault, "BuzzVault_UnknownToken");
        });
        it("should revert if reserves are invalid", async () => {
            await expect(
                vault.buy(token.address, ethers.utils.parseEther("1000000000000000000"), ethers.constants.AddressZero, { value: ethers.utils.parseEther("0.1") })
            ).to.be.revertedWithCustomError(vault, "BuzzVault_InvalidReserves");
        });
        it("should revert if user wants less than 0.001 token min", async () => {
            await expect(
                vault.buy(token.address, ethers.utils.parseEther("0.0001"), ethers.constants.AddressZero, { value: ethers.utils.parseEther("0.0000000000000001") })
            ).to.be.revertedWithCustomError(vault, "BuzzVault_InvalidMinTokenAmount");
        });
        it("should revert if user will get less than 0.001 token", async () => {
            await expect(
                vault.buy(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, { value: ethers.utils.parseEther("0.000000000000000001") })
            ).to.be.revertedWithCustomError(vault, "BuzzVault_InvalidMinTokenAmount");
        });
        it("should set a referral if one is provided", async () => {
            await vault
                .connect(user1Signer)
                .buy(token.address, ethers.utils.parseEther("0.001"), ownerSigner.address, { value: ethers.utils.parseEther("0.1") });
            expect(await referralManager.referredBy(user1Signer.address)).to.be.equal(ownerSigner.address);
        });
        it("should emit a trade event", async () => {
            await expect(
                vault
                    .connect(user1Signer)
                    .buy(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, { value: ethers.utils.parseEther("0.1") })
            ).to.emit(eventTracker, "Trade");
        });
        it("should transfer the 1% of msg.value to feeRecipient", async () => {
            const feeRecipientBalanceBefore = await ethers.provider.getBalance(feeRecipient);
            const msgValue = ethers.utils.parseEther("0.1");
            await vault.connect(user1Signer).buy(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, { value: msgValue });
            const feeRecipientBalanceAfter = await ethers.provider.getBalance(feeRecipient);
            expect(feeRecipientBalanceAfter.sub(feeRecipientBalanceBefore)).to.be.equal(msgValue.div(100)); // fee is 1%
        });
        // Add more tests
        it("should increase the BeraAmount and decrease the tokenBalance after the buy", async () => {
            const tokenInfoBefore = await vault.tokenInfo(token.address);
            const msgValue = ethers.utils.parseEther("0.01");
            await vault.connect(user1Signer).buy(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, { value: msgValue });
            const tokenInfoAfter = await vault.tokenInfo(token.address);
            const userTokenBalance = await token.balanceOf(user1Signer.address);
            const msgValueAfterFee = msgValue.sub(msgValue.div(100));

            const pricePerToken = calculateTokenPrice(msgValue, userTokenBalance);
            console.log("Price per token in Bera: ", pricePerToken);

            // check balances
            expect(tokenInfoAfter[0]).to.be.equal(tokenInfoBefore[0].sub(userTokenBalance));
            expect(tokenInfoAfter[1]).to.be.equal(tokenInfoBefore[1].add(msgValueAfterFee));
        });
        it("should init a pool and deposit liquidity if preconditions are met", async () => {
            const msgValue = ethers.utils.parseEther("3000");

            await vault.connect(user1Signer).buy(token.address, ethers.utils.parseEther("2800"), ethers.constants.AddressZero, {
                value: ethers.utils.parseEther("3000"),
            });

            //const getMarket = await vault.getMarketCapFor(token.address);
            //console.log("Market cap: ", getMarket.toString());

            const tokenInfoAfter = await vault.tokenInfo(token.address);
            const userTokenBalance = await token.balanceOf(user1Signer.address);

            const pricePerToken = calculateTokenPrice(msgValue, userTokenBalance);
            console.log("Price per token in Bera: ", pricePerToken);

            const tokenBalance = tokenInfoAfter[0];
            console.log("Token balance: ", tokenBalance.toString());

            // check balances
            expect(tokenInfoAfter[5]).to.be.equal(true);
        });
    });
    describe("sell", () => {
        beforeEach(async () => {
            await vault
                .connect(user1Signer)
                .buy(token.address, ethers.utils.parseEther("3"), ethers.constants.AddressZero, { value: ethers.utils.parseEther("3") });
        });
        it("should revert if token doesn't exist", async () => {
            await expect(
                vault.sell(ownerSigner.address, ethers.utils.parseEther("1"), 0, ethers.constants.AddressZero)
            ).to.be.revertedWithCustomError(vault, "BuzzVault_UnknownToken");
        });
        it("should revert if user balance is invalid", async () => {
            await expect(vault.sell(token.address, ethers.utils.parseEther("10000000000000000000000"), 0, ethers.constants.AddressZero)).to.be.revertedWithCustomError(
                vault,
                "BuzzVault_InvalidUserBalance"
            );
        });
        it("should revert if user wants to sell less than 0.001 token", async () => {
            await expect(vault.sell(token.address, ethers.utils.parseEther("0.0001"), 0, ethers.constants.AddressZero)).to.be.revertedWithCustomError(
                vault,
                "BuzzVault_InvalidMinTokenAmount"
            );
        });
        it("should emit a trade event", async () => {
            const userTokenBalance = await token.balanceOf(user1Signer.address);
            console.log("User token balance: ", userTokenBalance.toString());
            await token.connect(user1Signer).approve(vault.address, userTokenBalance);
            await expect(vault.connect(user1Signer).sell(token.address, userTokenBalance, 0, ethers.constants.AddressZero)).to.emit(
                eventTracker,
                "Trade"
            );
        });
        it("should increase the tokenBalance", async () => {
            const tokenInfoBefore = await vault.tokenInfo(token.address);
            const userTokenBalance = await token.balanceOf(user1Signer.address);
            console.log("User token balance: ", userTokenBalance.toString());
            await token.connect(user1Signer).approve(vault.address, userTokenBalance);
            await vault.connect(user1Signer).sell(token.address, userTokenBalance, 0, ethers.constants.AddressZero);
            const tokenInfoAfter = await vault.tokenInfo(token.address);

            expect(tokenInfoAfter[0]).to.be.equal(tokenInfoBefore[0].add(userTokenBalance));
        });
    });
});
