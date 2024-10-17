import {expect} from "chai";
import {ethers} from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import * as helpers from "@nomicfoundation/hardhat-network-helpers";
import { formatBytes32String } from "ethers/lib/utils";
import {BigNumber, Contract} from "ethers";

// Function to calculate the price per token in ETH
function calculateTokenPrice(etherSpent: BigNumber, tokensReceived: BigNumber) {
    // Calculate the price per token (ETH)
    const pricePerTokenBN = etherSpent.mul(ethers.BigNumber.from("10").pow(18)).div(tokensReceived);

    // Convert the result back to Ether format (as string with 18 decimals)
    const pricePerTokenInEther = ethers.utils.formatEther(pricePerTokenBN);

    return pricePerTokenInEther;
}

describe("BuzzVaultExponential Tests", () => {
    const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
    let feeRecipient: string;

    let ownerSigner: SignerWithAddress;
    let user1Signer: SignerWithAddress;
    let user2Signer: SignerWithAddress;
    let factory: Contract;
    let vault: Contract;
    let token: Contract;
    let referralManager: Contract;
    let eventTracker: Contract;
    let expVault: Contract;
    let bexLpToken: Contract;
    let crocQuery: Contract;
    let bexPriceDecoder: Contract;
    let create3Factory: Contract;
    let bexLiquidityManager: Contract;

    const directRefFeeBps = 1500; // 15% of protocol fee
    const indirectRefFeeBps = 100; // fixed 1%
    const payoutThreshold = 0;
    const crocSwapDexAddress = "0xAB827b1Cc3535A9e549EE387A6E9C3F02F481B49";
    let validUntil: number;

    beforeEach(async () => {
        validUntil = (await helpers.time.latest()) + ONE_YEAR_IN_SECS;

        [ownerSigner, user1Signer, user2Signer] = await ethers.getSigners();
        feeRecipient = ownerSigner.address;

        // Deploy create3factory
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

        // Deploy EventTracker
        const EventTracker = await ethers.getContractFactory("BuzzEventTracker");
        eventTracker = await EventTracker.connect(ownerSigner).deploy([]);

        // Deploy factory
        const Factory = await ethers.getContractFactory("BuzzTokenFactory");
        factory = await Factory.connect(ownerSigner).deploy(eventTracker.address, ownerSigner.address, create3Factory.address);

        // Deploy liquidity manager
        const BexLiquidityManager = await ethers.getContractFactory("BexLiquidityManager");
        bexLiquidityManager = await BexLiquidityManager.connect(ownerSigner).deploy(crocSwapDexAddress);

        // Deploy Exponential Vault
        const ExpVault = await ethers.getContractFactory("BuzzVaultExponential");
        expVault = await ExpVault.connect(ownerSigner).deploy(
            feeRecipient,
            factory.address,
            referralManager.address,
            eventTracker.address,
            bexPriceDecoder.address,
            bexLiquidityManager.address
        );
        // Admin: Set Vault in the ReferralManager
        await referralManager.connect(ownerSigner).setWhitelistedVault(expVault.address, true);

        // Admin: Set event setter contracts in EventTracker
        await eventTracker.connect(ownerSigner).setEventSetter(expVault.address, true);
        await eventTracker.connect(ownerSigner).setEventSetter(factory.address, true);

        // Admin: Set Vault as the factory's vault & enable token creation
        await factory.connect(ownerSigner).setVault(expVault.address, true);

        await factory.connect(ownerSigner).setAllowTokenCreation(true);
        // Create a token
        const tx = await factory.createToken("TEST", "TEST", "Test token is the best", "0x0", expVault.address, formatBytes32String("12345"));
        const receipt = await tx.wait();
        const tokenCreatedEvent = receipt.events?.find((x: any) => x.event === "TokenCreated");

        // Get token contract
        token = await ethers.getContractAt("BuzzToken", tokenCreatedEvent?.args?.token);
    });
    describe("constructor", () => {
        it("should set the factory address", async () => {
            expect(await expVault.factory()).to.be.equal(factory.address);
        });
        it("should set the feeRecipient address", async () => {
            expect(await expVault.feeRecipient()).to.be.equal(feeRecipient);
        });
        it("should set the referralManager address", async () => {
            expect(await expVault.referralManager()).to.be.equal(referralManager.address);
        });
        it("should set the eventTracker address", async () => {
            expect(await expVault.eventTracker()).to.be.equal(eventTracker.address);
        });
    });
    describe("registerToken", () => {
        beforeEach(async () => {});
        it("should register token transferring totalSupply", async () => {
            const tokenInfo = await expVault.tokenInfo(token.address);
            expect(await token.balanceOf(expVault.address)).to.be.equal(await token.totalSupply());
            //expect(tokenInfo.tokenBalance).to.be.equal(await token.totalSupply());
            //expect(tokenInfo.beraBalance).to.be.equal(0);
            expect(tokenInfo.bexListed).to.be.equal(false);

            //expect(tokenInfo.tokenBalance).to.be.equal(await token.balanceOf(expVault.address));
        });
        it("should revert if caller is not factory", async () => {
            await expect(expVault.connect(user1Signer).registerToken(factory.address, ethers.utils.parseEther("100"))).to.be.revertedWithCustomError(
                expVault,
                "BuzzVault_Unauthorized"
            );
        });
    });
    describe("buy", () => {
        beforeEach(async () => {});
        it("should handle multiple buys in succession", async () => {
            const initialVaultTokenBalance = await token.balanceOf(expVault.address);
            const initialUser1Balance = await ethers.provider.getBalance(user1Signer.address);
            const initialUser2Balance = await ethers.provider.getBalance(user2Signer.address);

            // Buy 1: user1 buys a small amount of tokens
            await expVault
                .connect(user1Signer)
                .buy(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, {value: ethers.utils.parseEther("0.01")});
            const vaultTokenBalanceAfterFirstBuy = await token.balanceOf(expVault.address);
            const user1BalanceAfterFirstBuy = await ethers.provider.getBalance(user1Signer.address);
            const tokenInfoAfterFirstBuy = await expVault.tokenInfo(token.address);

            console.log("Token balance after first buy:", vaultTokenBalanceAfterFirstBuy.toString());
            console.log("User1 BERA balance after first buy:", user1BalanceAfterFirstBuy.toString());
            console.log("Vault token info after first buy:", tokenInfoAfterFirstBuy);

            expect(vaultTokenBalanceAfterFirstBuy).to.be.below(initialVaultTokenBalance);

            // Buy 2: user2 buys using same BERA amount
            await expVault
                .connect(user2Signer)
                .buy(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, {value: ethers.utils.parseEther("0.01")});
            const vaultTokenBalanceAfterSecondBuy = await token.balanceOf(expVault.address);
            const user2BalanceAfterSecondBuy = await ethers.provider.getBalance(user2Signer.address);
            const tokenInfoAfterSecondBuy = await expVault.tokenInfo(token.address);

            console.log("Token balance after second buy:", vaultTokenBalanceAfterSecondBuy.toString());
            console.log("User2 BERA balance after second buy:", user2BalanceAfterSecondBuy.toString());
            console.log("Vault token info after second buy:", tokenInfoAfterSecondBuy);

            expect(vaultTokenBalanceAfterSecondBuy).to.be.below(vaultTokenBalanceAfterFirstBuy);

            // Assertions on balances, vault state, etc.
            expect(tokenInfoAfterSecondBuy.tokenBalance).to.be.below(tokenInfoAfterFirstBuy.tokenBalance);
            expect(tokenInfoAfterSecondBuy.beraBalance).to.be.above(tokenInfoAfterFirstBuy.beraBalance);

            console.log("Token address after salt exponential:", token.address);
            console.log("Factory address exponential:", factory.address);
            console.log("Owner address exponential:", ownerSigner.address);
        });
        it("should revert if reserves are invalid", async () => {
            await expect(
                expVault.buy(token.address, ethers.utils.parseEther("1000000000000000000"), ethers.constants.AddressZero, {value: ethers.utils.parseEther("0.1")})
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_InvalidReserves");
        });
        it("should revert if msg.value is zero", async () => {
            await expect(
                expVault.buy(token.address, ethers.utils.parseEther("1"), ethers.constants.AddressZero, {value: 0})
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_QuoteAmountZero");
        });
        it("should revert if token doesn't exist", async () => {
            await expect(
                expVault.buy(ownerSigner.address, ethers.utils.parseEther("1"), ethers.constants.AddressZero, {value: ethers.utils.parseEther("0.1")})
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_UnknownToken");
        });
        it("should revert if reserves are invalid", async () => {
            await expect(
                expVault.buy(token.address, ethers.utils.parseEther("1000000000000000000"), ethers.constants.AddressZero, {value: ethers.utils.parseEther("0.1")})
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_InvalidReserves");
        });
        it("should revert if user wants less than 0.001 token min", async () => {
            await expect(
                expVault.buy(token.address, ethers.utils.parseEther("0.0001"), ethers.constants.AddressZero, {value: ethers.utils.parseEther("0.00000000000000001")})
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_InvalidMinTokenAmount");
        });
        it("should revert if user will get less than 0.001 token", async () => {
            await expect(
                expVault.buy(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, {value: ethers.utils.parseEther("0.000000000000001")})
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_InvalidMinTokenAmount");
        });
        it("should set a referral if one is provided", async () => {
            await expVault
                .connect(user1Signer)
                .buy(token.address, ethers.utils.parseEther("0.001"), ownerSigner.address, {value: ethers.utils.parseEther("0.1")});
            expect(await referralManager.referredBy(user1Signer.address)).to.be.equal(ownerSigner.address);
        });
        it("should emit a trade event", async () => {
            await expect(
                expVault
                    .connect(user1Signer)
                    .buy(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, {value: ethers.utils.parseEther("0.1")})
            ).to.emit(eventTracker, "Trade");
        });
        it("should transfer the 1% of msg.value to feeRecipient", async () => {
            const feeRecipientBalanceBefore = await ethers.provider.getBalance(feeRecipient);
            const msgValue = ethers.utils.parseEther("0.1");
            await expVault.connect(user1Signer).buy(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, {value: msgValue});
            const feeRecipientBalanceAfter = await ethers.provider.getBalance(feeRecipient);
            expect(feeRecipientBalanceAfter.sub(feeRecipientBalanceBefore)).to.be.equal(msgValue.div(100)); // fee is 1%
        });
        // Add more tests
        it("should increase the BeraAmount and decrease the tokenBalance after the buy", async () => {
            const tokenInfoBefore = await expVault.tokenInfo(token.address);
            const msgValue = ethers.utils.parseEther("0.01");
            await expVault.connect(user1Signer).buy(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, {value: msgValue});
            const tokenInfoAfter = await expVault.tokenInfo(token.address);
            const userTokenBalance = await token.balanceOf(user1Signer.address);
            const msgValueAfterFee = msgValue.sub(msgValue.div(100));

            const pricePerToken = calculateTokenPrice(msgValue, userTokenBalance);
            console.log("Price per token in Bera: ", pricePerToken);

            // check balances
            expect(tokenInfoAfter[0]).to.be.equal(tokenInfoBefore[0].sub(userTokenBalance));
            expect(tokenInfoAfter[1]).to.be.equal(tokenInfoBefore[1].add(msgValueAfterFee));
        });
        it("should init a pool and deposit liquidity if preconditions are met", async () => {
            const msgValue = ethers.utils.parseEther("100");

            await expVault.connect(user1Signer).buy(token.address, ethers.utils.parseEther("100"), ethers.constants.AddressZero, {
                value: ethers.utils.parseEther("100"), 
            });

            const getMarket = await expVault.getMarketCapFor(token.address);
            console.log("Market cap: ", getMarket.toString());

            const tokenInfoAfter = await expVault.tokenInfo(token.address);
            const userTokenBalance = await token.balanceOf(user1Signer.address);

            const pricePerToken = calculateTokenPrice(msgValue, userTokenBalance);
            console.log("Price per token in BeraA: ", pricePerToken);

            const tokenBalance = tokenInfoAfter[0];
            console.log("Token balanceA: ", tokenBalance.toString());

            // check balances
            expect(tokenInfoAfter[5]).to.be.equal(true);
        });
    });
    describe("sell", () => {
        beforeEach(async () => {
            await expVault
                .connect(user1Signer)
                .buy(token.address, ethers.utils.parseEther("10"), ethers.constants.AddressZero, {value: ethers.utils.parseEther("10")});
        });
        it("should revert if token doesn't exist", async () => {
            await expect(
                expVault.sell(ownerSigner.address, ethers.utils.parseEther("1"), 0, ethers.constants.AddressZero)
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_UnknownToken");
        });
        it("should revert if user balance is invalid", async () => {
            await expect(expVault.sell(token.address, ethers.utils.parseEther("10000000000000000000000"), 0, ethers.constants.AddressZero)).to.be.revertedWithCustomError(
                expVault,
                "BuzzVault_InvalidUserBalance"
            );
        });
        it("should revert if user wants to sell less than 0.001 token", async () => {
            await expect(expVault.sell(token.address, ethers.utils.parseEther("0.0001"), 0, ethers.constants.AddressZero)).to.be.revertedWithCustomError(
                expVault,
                "BuzzVault_InvalidMinTokenAmount"
            );
        });
        it("should emit a trade event", async () => {
            const userTokenBalance = await token.balanceOf(user1Signer.address);
            await token.connect(user1Signer).approve(expVault.address, userTokenBalance);
            await expect(expVault.connect(user1Signer).sell(token.address, userTokenBalance, 0, ethers.constants.AddressZero)).to.emit(
                eventTracker,
                "Trade"
            );
        });
        it("should increase the tokenBalance", async () => {
            const tokenInfoBefore = await expVault.tokenInfo(token.address);
            const userTokenBalance = await token.balanceOf(user1Signer.address);
            await token.connect(user1Signer).approve(expVault.address, userTokenBalance);
            await expVault.connect(user1Signer).sell(token.address, userTokenBalance, 0, ethers.constants.AddressZero);
            const tokenInfoAfter = await expVault.tokenInfo(token.address);

            expect(tokenInfoAfter[0]).to.be.equal(tokenInfoBefore[0].add(userTokenBalance));
        });
    });
});
