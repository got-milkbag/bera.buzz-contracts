import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import * as helpers from "@nomicfoundation/hardhat-network-helpers";
import { formatBytes32String } from "ethers/lib/utils";
import { BigNumber, Contract } from "ethers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";

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

    let ownerSigner: SignerWithAddress;
    let user1Signer: SignerWithAddress;
    let user2Signer: SignerWithAddress;
    let treasury: SignerWithAddress;
    let factory: Contract;
    let token: Contract;
    let referralManager: Contract;
    let expVault: Contract;
    let create3Factory: Contract;
    let bexLiquidityManager: Contract;
    let wBera: Contract;
    let feeManager: Contract;
    let totalMintedSupply: BigNumber;

    const directRefFeeBps = 1500; // 15% of protocol fee
    const indirectRefFeeBps = 100; // fixed 1%
    const listingFee = ethers.utils.parseEther("0.002");
    const payoutThreshold = 0;
    const crocSwapDexAddress = "0xAB827b1Cc3535A9e549EE387A6E9C3F02F481B49";
    let validUntil: number;

    beforeEach(async () => {
        validUntil = (await helpers.time.latest()) + ONE_YEAR_IN_SECS;

        [ownerSigner, user1Signer, user2Signer, treasury] = await ethers.getSigners();

        // Deploy create3factory
        const Create3Factory = await ethers.getContractFactory("CREATE3FactoryMock");
        create3Factory = await Create3Factory.connect(ownerSigner).deploy();

        const bexLpTokenAddress = "0xd28d852cbcc68dcec922f6d5c7a8185dbaa104b7";
        const crocQueryAddress = "0x8685CE9Db06D40CBa73e3d09e6868FE476B5dC89";

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

        // Deploy Exponential Vault
        const ExpVault = await ethers.getContractFactory("BuzzVaultExponentialMock");
        expVault = await ExpVault.connect(ownerSigner).deploy(
            feeManager.address,
            factory.address,
            referralManager.address,
            bexLiquidityManager.address,
            wBera.address
        );

        await bexLiquidityManager.connect(ownerSigner).addVaults([expVault.address]);

        totalMintedSupply = ethers.utils.parseEther("1000000000");

        // Admin: Set Vault in the ReferralManager
        await referralManager.connect(ownerSigner).setWhitelistedVault(expVault.address, true);

        // Admin: Whitelist base token in Factory
        await factory.connect(ownerSigner).setAllowedBaseToken(wBera.address, ethers.utils.parseEther("0.001"), ethers.utils.parseEther("0.1"), true);

        // Admin: Set Vault as the factory's vault & enable token creation
        await factory.connect(ownerSigner).setVault(expVault.address, true);
        await factory.connect(ownerSigner).setAllowTokenCreation(true);

        // Create a token
        const tx = await factory.createToken(
            ["TEST", "TST"],
            [wBera.address, expVault.address],
            [ethers.utils.parseEther("100"), ethers.utils.parseEther("1000")],
            0,
            formatBytes32String("12345"),
            {
                value: listingFee,
            }
        );
        const receipt = await tx.wait();
        const tokenCreatedEvent = receipt.events?.find((x: any) => x.event === "TokenCreated");

        // Get token contract
        token = await ethers.getContractAt("BuzzToken", tokenCreatedEvent?.args?.token);

        // Deposit some Bera to WBera contract
        await wBera.deposit({ value: ethers.utils.parseEther("10") });
    });

    describe("constructor", () => {
        it("should set the feeManager address", async () => {
            expect(await expVault.FEE_MANAGER()).to.be.equal(feeManager.address);
        });
        it("should set the factory address", async () => {
            expect(await expVault.FACTORY()).to.be.equal(factory.address);
        });
        it("should set the referralManager address", async () => {
            expect(await expVault.REFERRAL_MANAGER()).to.be.equal(referralManager.address);
        });
        it("should set the bexLiquidityManager address", async () => {
            expect(await expVault.LIQUIDITY_MANAGER()).to.be.equal(bexLiquidityManager.address);
        });
        it("should set the wBera address", async () => {
            expect(await expVault.WBERA()).to.be.equal(wBera.address);
        });
    });
    describe("registerToken", () => {
        beforeEach(async () => { });
        it("should register token transferring totalSupply", async () => {
            const tokenInfo = await expVault.tokenInfo(token.address);
            expect(await token.balanceOf(expVault.address)).to.be.equal(await token.totalSupply());
            expect(tokenInfo.tokenBalance).to.be.equal(await token.totalSupply());
            expect(tokenInfo.baseBalance).to.be.equal(ethers.utils.parseEther("100"));
            expect(tokenInfo.bexListed).to.be.equal(false);

            expect(tokenInfo.tokenBalance).to.be.equal(await token.balanceOf(expVault.address));
        });
        it("should revert if caller is not factory", async () => {
            await expect(
                expVault
                    .connect(user1Signer)
                    .registerToken(factory.address, wBera.address, ethers.utils.parseEther("100"), 0, 0)
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_Unauthorized");
            //console.log("initial approx token price:", calculateTokenPrice(ethers.utils.parseEther("2.7"), await expVault.initialVirtualBase()));
            //console.log("initial Token price:", await expVault.initialTokenPrice());
            //console.log("initial Bera price:", await expVault.initialBeraPrice());
            //console.log("initial virtual base:", ethers.utils.formatEther(await expVault.initialVirtualBase()));
        });
    });
    describe("quote", () => {
        beforeEach(async () => {});
        it("should revert if amountIn is zero", async () => {
            await expect(expVault.quote(token.address, 0, true)).to.be.revertedWithCustomError(expVault, "BuzzVault_QuoteAmountZero");
        });
        it("should revert if token doesn't exist", async () => {
            await expect(expVault.quote(ownerSigner.address, ethers.utils.parseEther("1"), true)).to.be.revertedWithCustomError(
                expVault,
                "BuzzVault_UnknownToken"
            );
        });
        it("should revert if token is zero address", async () => {
            await expect(expVault.quote(ethers.constants.AddressZero, ethers.utils.parseEther("1"), true)).to.be.revertedWithCustomError(
                expVault,
                "BuzzVault_AddressZeroToken"
            );
        });
        it("should revert if the token has already been listed on Bex", async () => {
            await expVault.connect(user1Signer).buyNative(token.address, ethers.utils.parseEther("1000"), ethers.constants.AddressZero, user1Signer.address, {
                value: ethers.utils.parseEther("1500"),
            });
            await expect(expVault.quote(token.address, ethers.utils.parseEther("1"), true)).to.be.revertedWithCustomError(expVault, "BuzzVault_BexListed");
        });
        it("should return the quote for a given amount of tokens (buy)", async () => {
            const amount = ethers.utils.parseEther("1");

            const quote = await expVault.quote(token.address, amount, true);
            const balanceBefore = await token.balanceOf(user1Signer.address);
            await expVault
                .connect(ownerSigner)
                .buyNative(token.address, ethers.utils.parseEther("1000"), ethers.constants.AddressZero, user1Signer.address, {
                    value: amount,
                });
            const balanceAfter = await token.balanceOf(user1Signer.address);
            expect(quote).to.be.equal(balanceAfter.sub(balanceBefore));
        });
        it("should return the quote for a given amount of tokens (sell)", async () => {
            const baseAmount = ethers.utils.parseEther("1");

            // buy tokens initialy
            await expVault
                .connect(ownerSigner)
                .buyNative(token.address, ethers.utils.parseEther("1"), ethers.constants.AddressZero, ownerSigner.address, {
                    value: baseAmount,
                });

            const tokenBalance = await token.balanceOf(ownerSigner.address);
            const baseBalanceBefore = await wBera.balanceOf(ownerSigner.address);
            const quote = await expVault.quote(token.address, tokenBalance, false);

            await token.approve(expVault.address, tokenBalance);
            await expVault.connect(ownerSigner).sell(token.address, tokenBalance, 0, ethers.constants.AddressZero, ownerSigner.address, false);
            const baseBalanceAfter = await wBera.balanceOf(ownerSigner.address);
            expect(quote).to.be.equal(baseBalanceAfter.sub(baseBalanceBefore));
        });
        it("should return x0-x1 if quote amountIn is bigger than supply in curve (buy)", async () => {
            const quote = await expVault.quote(token.address, ethers.utils.parseEther("1000000000000000000000000000"), true);
            expect(quote).to.be.equal(ethers.utils.parseEther("900000000"));
        });
        it("should return y1-y0 if quote amountIn is bigger than supply in curve (sell)", async () => {
            const baseAmount = ethers.utils.parseEther("1");
            await expVault
                .connect(ownerSigner)
                .buyNative(token.address, ethers.utils.parseEther("1"), ethers.constants.AddressZero, ownerSigner.address, {
                    value: baseAmount,
                });
                
            const tokenInfo = await expVault.tokenInfo(token.address);
            const beraBalance = tokenInfo[3];
            const initialBera = tokenInfo[4];
            const resultingBera = beraBalance.sub(initialBera);

            const quote = await expVault.quote(token.address, ethers.utils.parseEther("1000000000000000000000000000"), false);
            expect(quote).to.be.equal(resultingBera.sub(await feeManager.quoteTradingFee(resultingBera)));
        });
    });
    describe("buyNative", () => {
        beforeEach(async () => { });
        it("should handle multiple buys in succession", async () => {
            const tokenInfo = await expVault.tokenInfo(token.address);
            const beraThreshold = tokenInfo[6];
            console.log("Quote threshold: ", beraThreshold.toString());

            const initialVaultTokenBalance = await token.balanceOf(expVault.address);
            const initialUser1Balance = await ethers.provider.getBalance(user1Signer.address);
            const initialUser2Balance = await ethers.provider.getBalance(user2Signer.address);

            // Buy 1: user1 buys a small amount of tokens
            await expVault
                .connect(user1Signer)
                .buyNative(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, user1Signer.address, { value: ethers.utils.parseEther("0.01") });
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
                .buyNative(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, user1Signer.address, { value: ethers.utils.parseEther("0.01") });
            const vaultTokenBalanceAfterSecondBuy = await token.balanceOf(expVault.address);
            const user2BalanceAfterSecondBuy = await ethers.provider.getBalance(user2Signer.address);
            const tokenInfoAfterSecondBuy = await expVault.tokenInfo(token.address);

            console.log("Token balance after second buy:", vaultTokenBalanceAfterSecondBuy.toString());
            console.log("User2 BERA balance after second buy:", user2BalanceAfterSecondBuy.toString());
            console.log("Vault token info after second buy:", tokenInfoAfterSecondBuy);

            expect(vaultTokenBalanceAfterSecondBuy).to.be.below(vaultTokenBalanceAfterFirstBuy);

            // Assertions on balances, vault state, etc.
            expect(tokenInfoAfterSecondBuy.tokenBalance).to.be.below(tokenInfoAfterFirstBuy.tokenBalance);
            expect(tokenInfoAfterSecondBuy.baseBalance).to.be.above(tokenInfoAfterFirstBuy.baseBalance);

            console.log("Token address after salt exponential:", token.address);
            console.log("Factory address exponential:", factory.address);
            console.log("Owner address exponential:", ownerSigner.address);
        });

        it("should revert if msg.value is zero", async () => {
            await expect(
                expVault.buyNative(token.address, ethers.utils.parseEther("1"), ethers.constants.AddressZero, user1Signer.address, { value: 0 })
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_QuoteAmountZero");
        });
        it("should revert if base token is not WBera", async () => {
            await expect(
                expVault.buyNative(ownerSigner.address, ethers.utils.parseEther("1"), ethers.constants.AddressZero, user1Signer.address, {
                    value: ethers.utils.parseEther("0.1"),
                })
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_NativeTradeUnsupported");
        });
        it("should send the tokens to the recipient, if it's a different address than the caller", async () => {
            await expVault
                .connect(ownerSigner)
                .buyNative(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, user1Signer.address, { value: ethers.utils.parseEther("0.1") });
            expect(await token.balanceOf(user1Signer.address)).to.be.greaterThan(0);
        });
        it("should emit the recipient address as the buyer", async () => {
            expect(await expVault
                .connect(ownerSigner)
                .buyNative(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, user1Signer.address, { value: ethers.utils.parseEther("0.1") }))
                .to.emit(expVault, "Trade")
                .withArgs(
                    user1Signer.address,
                    anyValue,
                    anyValue,
                    anyValue,
                    anyValue,
                    anyValue,
                    anyValue,
                    true
                );
        });
    });
    describe("buy (ERC20)", () => {
        beforeEach(async () => {
            await wBera.deposit({ value: ethers.utils.parseEther("1") });
        });
        it("should revert if token amount is zero", async () => {
            await wBera.approve(expVault.address, ethers.utils.parseEther("1"));
            await expect(expVault.buy(token.address, 0, 0, ethers.constants.AddressZero, user1Signer.address)).to
                .be.revertedWithCustomError(expVault, "BuzzVault_QuoteAmountZero");
        });
        it("should revert if token address is zero", async () => {
            await wBera.approve(expVault.address, ethers.utils.parseEther("1"));
            await expect(expVault.buy(ethers.constants.AddressZero, ethers.utils.parseEther("1"), ethers.utils.parseEther("1"), ethers.constants.AddressZero, user1Signer.address)).to
                .be.revertedWithCustomError(expVault, "BuzzVault_AddressZeroToken");
        });
        it("should revert if recipient address is zero", async () => {
            await wBera.approve(expVault.address, ethers.utils.parseEther("1"));
            await expect(expVault.buy(token.address, ethers.utils.parseEther("1"), ethers.utils.parseEther("1"), ethers.constants.AddressZero, ethers.constants.AddressZero)).to
                .be.revertedWithCustomError(expVault, "BuzzVault_AddressZeroRecipient");
        });
        it("should transfer the erc20 tokens", async () => {
            const balanceBefore = await wBera.balanceOf(ownerSigner.address);
            await wBera.connect(ownerSigner).approve(expVault.address, ethers.utils.parseEther("1"));
            await expVault.buy(token.address, ethers.utils.parseEther("1"), ethers.utils.parseEther("1"), ethers.constants.AddressZero, user1Signer.address,);
            expect(await wBera.balanceOf(ownerSigner.address)).to.be.equal(balanceBefore.sub(ethers.utils.parseEther("1")));
        });
        it("should send the tokens to the recipient, if it's a different address than the caller", async () => {
            await wBera.connect(ownerSigner).approve(expVault.address, ethers.utils.parseEther("1"));
            await expVault.buy(token.address, ethers.utils.parseEther("1"), ethers.utils.parseEther("1"), ethers.constants.AddressZero, user1Signer.address);
            expect(await token.balanceOf(user1Signer.address)).to.be.greaterThan(0);
        });
        it("should emit the recipient address as the buyer", async () => {
            await wBera.connect(ownerSigner).approve(expVault.address, ethers.utils.parseEther("1"));
            expect(await expVault
                .buy(token.address, ethers.utils.parseEther("1"), ethers.utils.parseEther("1"), ethers.constants.AddressZero, user1Signer.address))
                .to.emit(expVault, "Trade")
                .withArgs(
                    user1Signer.address,
                    anyValue,
                    anyValue,
                    anyValue,
                    anyValue,
                    anyValue,
                    anyValue,
                    true
                );
        });
    });
    describe("_buyTokens", () => {
        it("should revert if token doesn't exist", async () => {
            await wBera.deposit({ value: ethers.utils.parseEther("1") });
            await wBera.approve(expVault.address, ethers.utils.parseEther("1"));
            await expect(expVault.buy(wBera.address, ethers.utils.parseEther("1"), ethers.utils.parseEther("1"), ethers.constants.AddressZero, user1Signer.address,)).to
                .reverted;
            // fails in safeTransferFrom
        });
        it("should revert if token is already listed to Bex", async () => {
            await expVault.connect(user1Signer).buyNative(token.address, ethers.utils.parseEther("1000"), ethers.constants.AddressZero, user1Signer.address, {
                value: ethers.utils.parseEther("1500"),
            });
            await wBera.deposit({ value: ethers.utils.parseEther("1") });
            await wBera.approve(expVault.address, ethers.utils.parseEther("1"));
            await expect(
                expVault.buyNative(token.address, ethers.utils.parseEther("1000"), ethers.constants.AddressZero, user1Signer.address, {
                    value: ethers.utils.parseEther("1500"),
                })
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_BexListed");
            // fails in safeTransferFrom
        });
        it("should revert if reserves are invalid", async () => {
            await expect(
                expVault.buyNative(token.address, ethers.utils.parseEther("1000000000000000000"), ethers.constants.AddressZero, user1Signer.address, {
                    value: ethers.utils.parseEther("0.1"),
                })
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_InvalidReserves");
        });
        it("should set a referral if one is provided", async () => {
            await expVault
                .connect(user1Signer)
                .buyNative(token.address, ethers.utils.parseEther("0.001"), ownerSigner.address, user1Signer.address, { value: ethers.utils.parseEther("0.1") });
            expect(await referralManager.referredBy(user1Signer.address)).to.be.equal(ownerSigner.address);
        });
        it("should transfer the 1% of msg.value to treasury", async () => {
            const treasuryBalanceBefore = await wBera.balanceOf(treasury.address);
            const msgValue = ethers.utils.parseEther("0.1");
            await expVault
                .connect(user1Signer)
                .buyNative(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, user1Signer.address, { value: msgValue });
            const treasuryBalanceAfter = await wBera.balanceOf(treasury.address);
            const tradingFee = await feeManager.tradingFeeBps();
            expect(treasuryBalanceAfter.sub(treasuryBalanceBefore)).to.be.equal(msgValue.div(tradingFee)); // fee is 1%
        });
        it("should transfer the referral fee, and a lower trading fee", async () => {
            expect(await referralManager.getReferralRewardFor(ownerSigner.address, wBera.address)).to.be.equal(0);
            const treasuryBalanceBefore = await wBera.balanceOf(treasury.address);
            const msgValue = ethers.utils.parseEther("0.1");
            await expVault.connect(user1Signer).buyNative(token.address, ethers.utils.parseEther("0.001"), ownerSigner.address, user1Signer.address, { value: msgValue });
            const treasuryBalanceAfter = await wBera.balanceOf(treasury.address);
            const tradingFee = await feeManager.quoteTradingFee(msgValue);

            //calculate referral fee
            const refUserBps = await referralManager.getReferralBpsFor(user1Signer.address);
            const referralFee = tradingFee.mul(refUserBps).div(10000);
            expect(await referralManager.getReferralRewardFor(ownerSigner.address, wBera.address)).to.be.equal(referralFee);
            expect(treasuryBalanceAfter.sub(treasuryBalanceBefore)).to.be.equal(tradingFee.sub(referralFee));
        });
        it("should not collect a referral fee if trading fee is 0", async () => {
            await feeManager.connect(ownerSigner).setTradingFeeBps(0);
            const treasuryBalanceBefore = await wBera.balanceOf(treasury.address);
            const msgValue = ethers.utils.parseEther("0.1");
            await expVault.connect(user1Signer).buyNative(token.address, ethers.utils.parseEther("0.000000000001"), ownerSigner.address, user1Signer.address, { value: msgValue });
            const treasuryBalanceAfter = await wBera.balanceOf(treasury.address);

            expect(await referralManager.getReferralRewardFor(ownerSigner.address, wBera.address)).to.be.equal(0);
            expect(treasuryBalanceAfter.sub(treasuryBalanceBefore)).to.be.equal(0);
        });
        it("should transfer tokens to the user", async () => {
            const userBalanceBefore = await token.balanceOf(user1Signer.address);
            await expVault
                .connect(user1Signer)
                .buyNative(token.address, ethers.utils.parseEther("0.001"), ownerSigner.address, user1Signer.address, { value: ethers.utils.parseEther("0.1") });
            const userBalanceAfter = await token.balanceOf(user1Signer.address);
            expect(await userBalanceAfter.sub(userBalanceBefore)).to.be.greaterThan(userBalanceBefore);
        });
        it("should emit a trade event", async () => {
            await expect(
                expVault
                    .connect(user1Signer)
                    .buyNative(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, user1Signer.address, { value: ethers.utils.parseEther("0.1") })
            )
                .to.emit(expVault, "Trade")
                .withArgs(
                    user1Signer.address,
                    token.address,
                    wBera.address,
                    anyValue,
                    ethers.utils.parseEther("0.1"),
                    anyValue,
                    anyValue,
                    true
                );
        });
        // Add more tests
        it("should increase the baseAmount and decrease the tokenBalance after the buy", async () => {
            const tokenInfoBefore = await expVault.tokenInfo(token.address);
            const msgValue = ethers.utils.parseEther("0.01");
            await expVault
                .connect(user1Signer)
                .buyNative(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, user1Signer.address, { value: msgValue });
            const tokenInfoAfter = await expVault.tokenInfo(token.address);
            const userTokenBalance = await token.balanceOf(user1Signer.address);
            const msgValueAfterFee = msgValue.sub(msgValue.div(100));

            const pricePerToken = calculateTokenPrice(msgValue, userTokenBalance);
            console.log("Price per token in Bera: ", pricePerToken);
            console.log(
                "ABI decoded",
                ethers.utils.defaultAbiCoder.decode(["uint128"], "0x0000000000000000000000000000000000000000000000016a09e667f3bd0000")
            );

            // check balances
            expect(tokenInfoAfter.tokenBalance).to.be.equal(tokenInfoBefore.tokenBalance.sub(userTokenBalance));
            expect(tokenInfoAfter.baseBalance).to.be.equal(tokenInfoBefore.baseBalance.add(msgValueAfterFee));
        });
        it("should init a pool and deposit liquidity if preconditions are met", async () => {
            const msgValue = ethers.utils.parseEther("909.1");

            const tokenContractBalance = await token.balanceOf(expVault.address);
            console.log("Token contract balanceA: ", tokenContractBalance.toString());

            const userBaseBalanceBefore = await wBera.balanceOf(user1Signer.address);

            const tokenInfoBefore = await expVault.tokenInfo(token.address);
            const beraThreshold = tokenInfoBefore[6];
            console.log("Bera thresholdA: ", beraThreshold.toString());

            const tx = await expVault.connect(user1Signer).buyNative(token.address, ethers.utils.parseEther("1000"), ethers.constants.AddressZero, user1Signer.address, {
                value: msgValue,
            });
            const receipt = await tx.wait();

            const tokenInfoAfter = await expVault.tokenInfo(token.address);
            const userTokenBalance = await token.balanceOf(user1Signer.address);
            
            const userBaseBalanceAfter = await wBera.balanceOf(user1Signer.address);

            const tradeEvent = receipt.events?.find((x: any) => x.event === "Trade");
            const baseAmount = tradeEvent.args.baseAmount;

            const pricePerToken = calculateTokenPrice(baseAmount, userTokenBalance);
            console.log("Price per token in BeraA: ", pricePerToken);

            const tokenBalance = tokenInfoAfter[2];
            console.log("Token balanceA: ", tokenBalance.toString());

            const beraBalance = tokenInfoAfter[3];
            const initialBase = tokenInfoAfter[4];
            const beraThresholdAfter = tokenInfoAfter[5];
            const quoteThresholdAfter = tokenInfoAfter[6];
            const k = tokenInfoAfter[7];
            const bexListed = tokenInfoAfter[1];

            // check balances
            expect(tokenBalance).to.be.equal(0);
            expect(beraBalance).to.be.equal(0);
            expect(initialBase).to.be.equal(0);
            expect(beraThresholdAfter).to.be.equal(0);
            expect(quoteThresholdAfter).to.be.equal(0);
            expect(k).to.be.equal(0);
            expect(bexListed).to.be.equal(true);
            expect(userBaseBalanceAfter.sub(userBaseBalanceBefore)).to.be.gt(0);
        });
    });
    describe("sell", () => {
        beforeEach(async () => {
            await expVault
                .connect(user1Signer)
                .buyNative(token.address, ethers.utils.parseEther("1"), ethers.constants.AddressZero, user1Signer.address, { value: ethers.utils.parseEther("2") });
            await token.connect(user1Signer).approve(expVault.address, await token.balanceOf(user1Signer.address));
        });
        it("should revert if the token amount is zero", async () => {
            await expect(expVault.sell(ownerSigner.address, 0, 0, ethers.constants.AddressZero,  user1Signer.address, false)).to.be.revertedWithCustomError(
                expVault,
                "BuzzVault_QuoteAmountZero"
            );
        });
        it("should revert if token doesn't exist", async () => {
            await expect(
                expVault.sell(ownerSigner.address, ethers.utils.parseEther("1"), 0, ethers.constants.AddressZero, user1Signer.address, false)
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_UnknownToken");
        });
        it("should revert if token is already listed to Bex", async () => {
            await expVault.connect(user1Signer).buyNative(token.address, ethers.utils.parseEther("1"), ethers.constants.AddressZero, user1Signer.address, {
                value: ethers.utils.parseEther("909"),
            });
            await token.approve(expVault.address, ethers.utils.parseEther("2"));
            await expect(
                expVault.connect(user1Signer).sell(token.address, ethers.utils.parseEther("2"), ethers.utils.parseEther("2"), ethers.constants.AddressZero, user1Signer.address, false)
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_BexListed");
        });
        it("should revert if user balance is invalid", async () => {
            await expect(
                expVault.sell(token.address, ethers.utils.parseEther("10000000000000000000000"), 0, ethers.constants.AddressZero, user1Signer.address, false)
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_InvalidUserBalance");
        });
        it("should revert if token is address zero", async () => {
            await expect(
                expVault.sell(ethers.constants.AddressZero, ethers.utils.parseEther("1"), 0, ethers.constants.AddressZero, user1Signer.address, false)
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_AddressZeroToken");
        });
        it("should revert if recipient is address zero", async () => {
            await expect(
                expVault.sell(token.address, ethers.utils.parseEther("1"), 0, ethers.constants.AddressZero, ethers.constants.AddressZero, false)
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_AddressZeroRecipient");
        });
        it("should set a referral if one is provided", async () => {
            await expVault
                .connect(user1Signer)
                .sell(token.address, ethers.utils.parseEther("10000"), ethers.utils.parseEther("0.00000001"), ownerSigner.address, user1Signer.address, false);
            expect(await referralManager.referredBy(user1Signer.address)).to.be.equal(ownerSigner.address);
        });
        it("should revert if slippage is exceeded", async () => {
            const userBalance = await token.balanceOf(user1Signer.address);
            await expect(
                expVault
                    .connect(user1Signer)
                    .sell(token.address, userBalance.sub(1), ethers.utils.parseEther("1000000000000000000"), ethers.constants.AddressZero, user1Signer.address, false)
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_SlippageExceeded");
        });
        it("should transfer the 1% of msg.value to treasury", async () => {
            const treasuryBalanceBefore = await wBera.balanceOf(treasury.address);
            const sellAmount = ethers.utils.parseEther("10000");

            // Calculate the expected gross base amount before calling sell
            const tokenInfoPre = await expVault.tokenInfo(token.address);
            const expectedGrossBaseAmount = await expVault.calculateSellPrice_(sellAmount, tokenInfoPre[2], tokenInfoPre[3], tokenInfoPre[7]);

            await expVault.connect(user1Signer).sell(token.address, sellAmount, ethers.utils.parseEther("0.0000000001"), ethers.constants.AddressZero, user1Signer.address, false);

            const treasuryBalanceAfter = await wBera.balanceOf(treasury.address);

            const tradingFee = await feeManager.quoteTradingFee(expectedGrossBaseAmount);
            expect(treasuryBalanceAfter.sub(treasuryBalanceBefore)).to.be.equal(tradingFee);
        });
        it("should transfer the referral fee, and a lower trading fee", async () => {
            expect(await referralManager.getReferralRewardFor(ownerSigner.address, wBera.address)).to.be.equal(0);

            const treasuryBalanceBefore = await wBera.balanceOf(treasury.address);
            const sellAmount = ethers.utils.parseEther("10000");

            // Calculate the expected gross base amount before calling sell
            const tokenInfoPre = await expVault.tokenInfo(token.address);
            const expectedGrossBaseAmount = await expVault.calculateSellPrice_(sellAmount, tokenInfoPre[2], tokenInfoPre[3], tokenInfoPre[7]);

            await expVault.connect(user1Signer).sell(token.address, sellAmount, ethers.utils.parseEther("0.000000001"), ethers.constants.AddressZero, user1Signer.address, false);

            const treasuryBalanceAfter = await wBera.balanceOf(treasury.address);
            const tradingFee = await feeManager.quoteTradingFee(expectedGrossBaseAmount);

            // Calculate referral fee
            const refUserBps = await referralManager.getReferralBpsFor(user1Signer.address);
            const referralFee = tradingFee.mul(refUserBps).div(10000);

            expect(await referralManager.getReferralRewardFor(ownerSigner.address, wBera.address)).to.be.equal(referralFee);
            expect(treasuryBalanceAfter.sub(treasuryBalanceBefore)).to.be.equal(tradingFee.sub(referralFee));
            
        });
        it("should not collect a referral fee if trading fee is 0", async () => {
            await feeManager.connect(ownerSigner).setTradingFeeBps(0);
            const treasuryBalanceBefore = await wBera.balanceOf(treasury.address);
            await expVault
                .connect(user1Signer)
                .sell(token.address, ethers.utils.parseEther("10000"), ethers.utils.parseEther("0.00000001"), ethers.constants.AddressZero, user1Signer.address, false);
            const treasuryBalanceAfter = await wBera.balanceOf(treasury.address);

            expect(await referralManager.getReferralRewardFor(ownerSigner.address, wBera.address)).to.be.equal(0);
            expect(treasuryBalanceAfter.sub(treasuryBalanceBefore)).to.be.equal(0);
        });
        it("should transfer quote tokens from the user", async () => {
            const userBalanceBefore = await token.balanceOf(user1Signer.address);
            const amountToSell = ethers.utils.parseEther("10000");
            await expVault.connect(user1Signer).sell(token.address, amountToSell, ethers.utils.parseEther("0.000000001"), ownerSigner.address, user1Signer.address, false);
            const userBalanceAfter = await token.balanceOf(user1Signer.address);
            expect(await userBalanceBefore.sub(userBalanceAfter)).to.be.equal(amountToSell);
        });
        it("should transfer base tokens to the user", async () => {
            const userBalanceBefore = await wBera.balanceOf(user1Signer.address);
            await expVault
                .connect(user1Signer)
                .sell(token.address, ethers.utils.parseEther("10000"), ethers.utils.parseEther("0.00000000001"), ownerSigner.address, user1Signer.address, false);
            const userBalanceAfter = await wBera.balanceOf(user1Signer.address);
            expect(await userBalanceAfter.sub(userBalanceBefore)).to.be.greaterThan(userBalanceBefore);
        });
        it("should emit a trade event", async () => {
            const userTokenBalance = await token.balanceOf(user1Signer.address);
            await token.connect(user1Signer).approve(expVault.address, userTokenBalance);
            await expect(expVault.connect(user1Signer).sell(token.address, userTokenBalance, 0, ethers.constants.AddressZero, user1Signer.address, false))
                .to.emit(expVault, "Trade")
                .withArgs(
                    user1Signer.address,
                    token.address,
                    wBera.address,
                    userTokenBalance,
                    anyValue,
                    anyValue,
                    anyValue,
                    false
                );
        });
        it("should unwrap the wrapped bera", async () => {
            const userBalanceBefore = await ethers.provider.getBalance(user1Signer.address);
            const amountToSell = ethers.utils.parseEther("100");

            const approveTx = await token.connect(user1Signer).approve(expVault.address, amountToSell);
            const sellTx = await expVault.connect(user1Signer).sell(token.address, amountToSell, 0, ethers.constants.AddressZero, user1Signer.address, true);
            const approveReceipt = await approveTx.wait();
            const sellReceipt = await sellTx.wait();
            const gasUsed = approveReceipt.cumulativeGasUsed.mul(approveReceipt.effectiveGasPrice).add(sellReceipt.cumulativeGasUsed.mul(sellReceipt.effectiveGasPrice));

            const tradeEvent = sellReceipt.events?.find((x: any) => x.event === "Trade");
            const baseAmount = tradeEvent.args.baseAmount;

            expect(await ethers.provider.getBalance(user1Signer.address)).to.be.equal(userBalanceBefore.add(baseAmount).sub(gasUsed));

        });
        it("should increase the tokenBalance in the vault", async () => {
            const tokenInfoBefore = await expVault.tokenInfo(token.address);
            const userTokenBalance = await token.balanceOf(user1Signer.address);
            await token.connect(user1Signer).approve(expVault.address, userTokenBalance);
            await expVault.connect(user1Signer).sell(token.address, userTokenBalance, 0, ethers.constants.AddressZero, user1Signer.address, false);
            const tokenInfoAfter = await expVault.tokenInfo(token.address);

            expect(tokenInfoAfter[2]).to.be.equal(tokenInfoBefore[2].add(userTokenBalance));
        });
    });
    describe("pause", () => {
        beforeEach(async () => {});
        it("should pause the contract", async () => {
            await expVault.pause();
            expect(await expVault.paused()).to.be.true;
        });
        it("should emit a Paused event", async () => {
            await expect(expVault.pause()).to.emit(expVault, "Paused");
        });
        it("should revert if the caller is not the owner", async () => {
            await expect(expVault.connect(treasury).pause()).to.be.revertedWith("Ownable: caller is not the owner");
        });
        it("should not allow calling buy", async () => {
            await expVault.pause();
            await wBera.deposit({ value: ethers.utils.parseEther("1") });
            await wBera.connect(ownerSigner).approve(expVault.address, ethers.utils.parseEther("1"));
            await expect(expVault.buy(token.address, ethers.utils.parseEther("1"), ethers.utils.parseEther("1"), ethers.constants.AddressZero, user1Signer.address, )).to.be.revertedWith("Pausable: paused");
        });
        it("should not allow calling sell", async () => {
            await expVault.pause();
            const userTokenBalance = await token.balanceOf(user1Signer.address);
            await token.connect(user1Signer).approve(expVault.address, userTokenBalance);
            await expect(expVault.connect(user1Signer).sell(token.address, userTokenBalance, 0, ethers.constants.AddressZero, user1Signer.address, false)).to.be.revertedWith("Pausable: paused");
        });
        it("should not allow calling buyNative", async () => {
            await expVault.pause();
            await expect(expVault.connect(user1Signer).buyNative(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, user1Signer.address, { value: ethers.utils.parseEther("0.01") })).to.be.revertedWith("Pausable: paused");
        });
    });
    describe("unpause", () => {
        beforeEach(async () => {
            await expVault.pause();
        });
        it("should unpause the contract", async () => {
            await expVault.unpause();
            expect(await expVault.paused()).to.be.false;
        });
        it("should emit a Unpaused event", async () => {
            expect(await expVault.unpause()).to.emit(expVault, "Unpaused");
        });
        it("should revert if the caller is not the owner", async () => {
            await expect(expVault.connect(treasury).unpause()).to.be.revertedWith("Ownable: caller is not the owner");
        });
        it("should allow calling buy", async () => {
            await expVault.unpause();
            await wBera.deposit({ value: ethers.utils.parseEther("1") });

            const balanceBefore = await wBera.balanceOf(ownerSigner.address);
            await wBera.connect(ownerSigner).approve(expVault.address, ethers.utils.parseEther("1"));
            await expVault.buy(token.address, ethers.utils.parseEther("1"), ethers.utils.parseEther("1"), ethers.constants.AddressZero, ownerSigner.address);
            expect(await wBera.balanceOf(ownerSigner.address)).to.be.equal(balanceBefore.sub(ethers.utils.parseEther("1")));
        });
        it("should allow calling sell", async () => {
            await expVault.unpause();
            await expVault
                .connect(user1Signer)
                .buyNative(token.address, ethers.utils.parseEther("0.000001"), ethers.constants.AddressZero, user1Signer.address, { value: ethers.utils.parseEther("0.1") });
            await token.connect(user1Signer).approve(expVault.address, await token.balanceOf(user1Signer.address));

            const tokenInfoBefore = await expVault.tokenInfo(token.address);
            const userTokenBalance = await token.balanceOf(user1Signer.address);
            await token.connect(user1Signer).approve(expVault.address, userTokenBalance);
            await expVault.connect(user1Signer).sell(token.address, userTokenBalance, 0, ethers.constants.AddressZero, user1Signer.address, false);
            const tokenInfoAfter = await expVault.tokenInfo(token.address);
            expect(tokenInfoAfter[2]).to.be.equal(tokenInfoBefore[2].add(userTokenBalance));
        });
        it("should allow calling buyNative", async () => {
            await expVault.unpause();
            const userBalanceBefore = await token.balanceOf(user1Signer.address);
            await expVault
                .connect(user1Signer)
                .buyNative(token.address, ethers.utils.parseEther("0.001"), ownerSigner.address, user1Signer.address, { value: ethers.utils.parseEther("0.1") });
            const userBalanceAfter = await token.balanceOf(user1Signer.address);
            expect(await userBalanceAfter.sub(userBalanceBefore)).to.be.greaterThan(userBalanceBefore);
        });
    });
});
