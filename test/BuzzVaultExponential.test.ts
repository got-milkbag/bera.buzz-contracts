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
    let bexPriceDecoder: Contract;
    let create3Factory: Contract;
    let bexLiquidityManager: Contract;
    let wBera: Contract;
    let feeManager: Contract;

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

        /*
        // Deploy mock BexLpToken
        const BexLpToken = await ethers.getContractFactory("BexLPTokenMock");
        bexLpToken = await BexLpToken.connect(ownerSigner).deploy(36000, ethers.constants.AddressZero, ethers.constants.AddressZero);

        //Deploy mock ICrocQuery
        const ICrocQuery = await ethers.getContractFactory("CrocQueryMock");
        crocQuery = await ICrocQuery.connect(ownerSigner).deploy(ethers.BigNumber.from("83238796252293901415"));*/

        const bexLpTokenAddress = "0xd28d852cbcc68dcec922f6d5c7a8185dbaa104b7";
        const crocQueryAddress = "0x8685CE9Db06D40CBa73e3d09e6868FE476B5dC89";
        // Deploy BexPriceDecoder
        const BexPriceDecoder = await ethers.getContractFactory("BexPriceDecoder");
        bexPriceDecoder = await BexPriceDecoder.connect(ownerSigner).deploy(bexLpTokenAddress, crocQueryAddress);

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
        await referralManager.connect(ownerSigner).setWhitelistedVault(expVault.address, true);

        // Admin: Whitelist base token in Factory
        await factory.connect(ownerSigner).setAllowedBaseToken(wBera.address, true);

        // Admin: Set Vault as the factory's vault & enable token creation
        await factory.connect(ownerSigner).setVault(expVault.address, true);
        await factory.connect(ownerSigner).setAllowTokenCreation(true);

        // Create a token
        const tx = await factory.createToken(
            ["TEST", "TST"],
            [wBera.address, expVault.address],
            [ethers.utils.parseEther("2.22"), BigNumber.from("3350000000")],
            0,
            formatBytes32String("12345"),
            ethers.utils.parseEther("69420"),
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
            expect(await expVault.feeManager()).to.be.equal(feeManager.address);
        });
        it("should set the factory address", async () => {
            expect(await expVault.factory()).to.be.equal(factory.address);
        });
        it("should set the referralManager address", async () => {
            expect(await expVault.referralManager()).to.be.equal(referralManager.address);
        });
        it("should set the bexPriceDecoder address", async () => {
            expect(await expVault.priceDecoder()).to.be.equal(bexPriceDecoder.address);
        });
        it("should set the bexLiquidityManager address", async () => {
            expect(await expVault.liquidityManager()).to.be.equal(bexLiquidityManager.address);
        });
        it("should set the wBera address", async () => {
            expect(await expVault.wbera()).to.be.equal(wBera.address);
        });
    });
    describe("registerToken", () => {
        beforeEach(async () => { });
        it("should register token transferring totalSupply", async () => {
            const tokenInfo = await expVault.tokenInfo(token.address);
            expect(await token.balanceOf(expVault.address)).to.be.equal(await token.totalSupply());
            expect(tokenInfo.tokenBalance).to.be.equal(await token.totalSupply());
            expect(tokenInfo.baseBalance).to.be.equal(0);
            expect(tokenInfo.bexListed).to.be.equal(false);

            expect(tokenInfo.tokenBalance).to.be.equal(await token.balanceOf(expVault.address));
        });
        it("should revert if caller is not factory", async () => {
            await expect(
                expVault
                    .connect(user1Signer)
                    .registerToken(factory.address, wBera.address, ethers.utils.parseEther("100"), ethers.utils.parseEther("69420"), 0, 0)
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_Unauthorized");
            //console.log("initial approx token price:", calculateTokenPrice(ethers.utils.parseEther("2.7"), await expVault.initialVirtualBase()));
            //console.log("initial Token price:", await expVault.initialTokenPrice());
            //console.log("initial Bera price:", await expVault.initialBeraPrice());
            //console.log("initial virtual base:", ethers.utils.formatEther(await expVault.initialVirtualBase()));
        });
    });
    describe("buyNative", () => {
        beforeEach(async () => { });
        it("should handle multiple buys in succession", async () => {
            const initialVaultTokenBalance = await token.balanceOf(expVault.address);
            const initialUser1Balance = await ethers.provider.getBalance(user1Signer.address);
            const initialUser2Balance = await ethers.provider.getBalance(user2Signer.address);

            // Buy 1: user1 buys a small amount of tokens
            await expVault
                .connect(user1Signer)
                .buyNative(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, { value: ethers.utils.parseEther("0.01") });
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
                .buyNative(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, { value: ethers.utils.parseEther("0.01") });
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
                expVault.buyNative(token.address, ethers.utils.parseEther("1"), ethers.constants.AddressZero, { value: 0 })
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_QuoteAmountZero");
        });
        it("should revert if base token is not WBera", async () => {
            await expect(
                expVault.buyNative(ownerSigner.address, ethers.utils.parseEther("1"), ethers.constants.AddressZero, {
                    value: ethers.utils.parseEther("0.1"),
                })
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_NativeTradeUnsupported");
        });
    });
    describe("buy (ERC20)", () => {
        beforeEach(async () => {
            await wBera.deposit({ value: ethers.utils.parseEther("1") });
        });
        it("should transfer the erc20 tokens", async () => {
            const balanceBefore = await wBera.balanceOf(ownerSigner.address);
            await wBera.connect(ownerSigner).approve(expVault.address, ethers.utils.parseEther("1"));
            await expVault.buy(token.address, ethers.utils.parseEther("1"), ethers.utils.parseEther("1"), ethers.constants.AddressZero);
            expect(await wBera.balanceOf(ownerSigner.address)).to.be.equal(balanceBefore.sub(ethers.utils.parseEther("1")));
        });
    });
    describe("_buyTokens", () => {
        it("should revert if user wants less than 0.001 token min", async () => {
            await expect(
                expVault.buyNative(token.address, ethers.utils.parseEther("0.0001"), ethers.constants.AddressZero, {
                    value: ethers.utils.parseEther("0.00000000000000001"),
                })
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_InvalidMinTokenAmount");
        });
        it("should revert if token doesn't exist", async () => {
            await wBera.deposit({ value: ethers.utils.parseEther("1") });
            await wBera.approve(expVault.address, ethers.utils.parseEther("1"));
            await expect(expVault.buy(wBera.address, ethers.utils.parseEther("1"), ethers.utils.parseEther("1"), ethers.constants.AddressZero)).to
                .reverted;
            // fails in safeTransferFrom
        });
        it("should revert if token is already listed to Bex", async () => {
            await expVault.connect(user1Signer).buyNative(token.address, ethers.utils.parseEther("1000"), ethers.constants.AddressZero, {
                value: ethers.utils.parseEther("1500"),
            });
            await wBera.deposit({ value: ethers.utils.parseEther("1") });
            await wBera.approve(expVault.address, ethers.utils.parseEther("1"));
            await expect(
                expVault.buyNative(token.address, ethers.utils.parseEther("1000"), ethers.constants.AddressZero, {
                    value: ethers.utils.parseEther("1500"),
                })
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_UnknownToken");
            // fails in safeTransferFrom
        });
        it("should revert if reserves are invalid", async () => {
            await expect(
                expVault.buyNative(token.address, ethers.utils.parseEther("1000000000000000000"), ethers.constants.AddressZero, {
                    value: ethers.utils.parseEther("0.1"),
                })
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_InvalidReserves");
        });
        it("should set a referral if one is provided", async () => {
            await expVault
                .connect(user1Signer)
                .buyNative(token.address, ethers.utils.parseEther("0.001"), ownerSigner.address, { value: ethers.utils.parseEther("0.1") });
            expect(await referralManager.referredBy(user1Signer.address)).to.be.equal(ownerSigner.address);
        });
        it("should revert if user will get less than 0.001 token", async () => {
            await expect(
                expVault.buyNative(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, {
                    value: ethers.utils.parseEther("0.000000000000001"),
                })
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_InvalidMinTokenAmount");
        });
        it("should transfer the 1% of msg.value to treasury", async () => {
            const treasuryBalanceBefore = await wBera.balanceOf(treasury.address);
            const msgValue = ethers.utils.parseEther("0.1");
            await expVault
                .connect(user1Signer)
                .buyNative(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, { value: msgValue });
            const treasuryBalanceAfter = await wBera.balanceOf(treasury.address);
            const tradingFee = await feeManager.tradingFeeBps();
            expect(treasuryBalanceAfter.sub(treasuryBalanceBefore)).to.be.equal(msgValue.div(tradingFee)); // fee is 1%
        });
        it("should transfer the referral fee, and a lower trading fee", async () => {
            expect(await referralManager.getReferralRewardFor(ownerSigner.address, wBera.address)).to.be.equal(0);
            const treasuryBalanceBefore = await wBera.balanceOf(treasury.address);
            const msgValue = ethers.utils.parseEther("0.1");
            await expVault.connect(user1Signer).buyNative(token.address, ethers.utils.parseEther("0.001"), ownerSigner.address, { value: msgValue });
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
            await expVault.connect(user1Signer).buyNative(token.address, ethers.utils.parseEther("0.001"), ownerSigner.address, { value: msgValue });
            const treasuryBalanceAfter = await wBera.balanceOf(treasury.address);

            expect(await referralManager.getReferralRewardFor(ownerSigner.address, wBera.address)).to.be.equal(0);
            expect(treasuryBalanceAfter.sub(treasuryBalanceBefore)).to.be.equal(0);
        });
        it("should transfer tokens to the user", async () => {
            const userBalanceBefore = await token.balanceOf(user1Signer.address);
            await expVault
                .connect(user1Signer)
                .buyNative(token.address, ethers.utils.parseEther("0.001"), ownerSigner.address, { value: ethers.utils.parseEther("0.1") });
            const userBalanceAfter = await token.balanceOf(user1Signer.address);
            expect(await userBalanceAfter.sub(userBalanceBefore)).to.be.greaterThan(userBalanceBefore);
        });
        it("should emit a trade event", async () => {
            await expect(
                expVault
                    .connect(user1Signer)
                    .buyNative(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, { value: ethers.utils.parseEther("0.1") })
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
                    anyValue,
                    anyValue,
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
                .buyNative(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, { value: msgValue });
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
            const msgValue = ethers.utils.parseEther("830");

            const tokenContractBalance = await token.balanceOf(expVault.address);
            console.log("Token contract balanceA: ", tokenContractBalance.toString());

            const tokenInfoBefore = await expVault.tokenInfo(token.address);
            const beraThreshold = tokenInfoBefore[6];
            console.log("Bera thresholdA: ", beraThreshold.toString());

            const beraPrice = await expVault.getBeraUsdPrice();
            console.log("Bera priceA: ", beraPrice.toString());

            await expVault.connect(user1Signer).buyNative(token.address, ethers.utils.parseEther("1000"), ethers.constants.AddressZero, {
                value: ethers.utils.parseEther("1500"),
            });

            const tokenInfoAfter = await expVault.tokenInfo(token.address);
            const userTokenBalance = await token.balanceOf(user1Signer.address);

            const pricePerToken = calculateTokenPrice(msgValue, userTokenBalance);
            console.log("Price per token in BeraA: ", pricePerToken);

            const tokenBalance = tokenInfoAfter[2];
            console.log("Token balanceA: ", tokenBalance.toString());

            const beraBalance = tokenInfoAfter[2];
            const lastPrice = tokenInfoAfter[3];
            const lastBeraPrice = tokenInfoAfter[4];
            const currentPrice = tokenInfoAfter[5];
            const currentBeraPrice = tokenInfoAfter[6];
            const beraThresholdAfter = tokenInfoAfter[7];
            const bexListed = tokenInfoAfter[11];
            const lpConduit = tokenInfoAfter[1];

            console.log("Lp conduit address: ", lpConduit);

            // Get LP token contract
            const lpToken = await ethers.getContractAt("CrocLpErc20", lpConduit);

            // check balances
            expect(tokenBalance).to.be.equal(0);
            expect(beraBalance).to.be.equal(0);
            expect(lastPrice).to.be.equal(0);
            expect(lastBeraPrice).to.be.equal(0);
            expect(currentPrice).to.be.equal(0);
            expect(currentBeraPrice).to.be.equal(0);
            expect(beraThresholdAfter).to.be.equal(0);
            expect(bexListed).to.be.equal(true);
            expect(await lpToken.balanceOf(bexLiquidityManager.address)).to.be.equal(0);
        });
    });
    describe("sell", () => {
        beforeEach(async () => {
            await expVault
                .connect(user1Signer)
                .buyNative(token.address, ethers.utils.parseEther("3"), ethers.constants.AddressZero, { value: ethers.utils.parseEther("3") });
            await token.connect(user1Signer).approve(expVault.address, await token.balanceOf(user1Signer.address));
        });
        it("should revert if the token amount is zero", async () => {
            await expect(expVault.sell(ownerSigner.address, 0, 0, ethers.constants.AddressZero, false)).to.be.revertedWithCustomError(
                expVault,
                "BuzzVault_QuoteAmountZero"
            );
        });
        it("should revert if the token amount to sell is less than the MIN_TOKEN_AMOUNT", async () => {
            const MIN_TOKEN_AMOUNT = await expVault.MIN_TOKEN_AMOUNT();
            await expect(
                expVault.sell(ownerSigner.address, MIN_TOKEN_AMOUNT.sub(1), 0, ethers.constants.AddressZero, false)
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_InvalidMinTokenAmount");
        });
        it("should revert if token doesn't exist", async () => {
            await expect(
                expVault.sell(ownerSigner.address, ethers.utils.parseEther("1"), 0, ethers.constants.AddressZero, false)
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_UnknownToken");
        });
        it("should revert if token is already listed to Bex", async () => {
            await expVault.connect(user1Signer).buyNative(token.address, ethers.utils.parseEther("1000"), ethers.constants.AddressZero, {
                value: ethers.utils.parseEther("1500"),
            });
            await token.approve(expVault.address, ethers.utils.parseEther("2"));
            await expect(
                expVault.sell(token.address, ethers.utils.parseEther("2"), ethers.utils.parseEther("2"), ethers.constants.AddressZero, false)
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_UnknownToken");
        });
        it("should revert if user balance is invalid", async () => {
            await expect(
                expVault.sell(token.address, ethers.utils.parseEther("10000000000000000000000"), 0, ethers.constants.AddressZero, false)
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_InvalidUserBalance");
        });
        it("should set a referral if one is provided", async () => {
            await expVault
                .connect(user1Signer)
                .sell(token.address, ethers.utils.parseEther("10000"), ethers.utils.parseEther("0.0001"), ownerSigner.address, false);
            expect(await referralManager.referredBy(user1Signer.address)).to.be.equal(ownerSigner.address);
        });
        it("should revert if slippage is exceeded", async () => {
            const userBalance = await token.balanceOf(user1Signer.address);
            await expect(
                expVault
                    .connect(user1Signer)
                    .sell(token.address, userBalance.sub(1), ethers.utils.parseEther("1000000000000000000"), ethers.constants.AddressZero, false)
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_SlippageExceeded");
        });
        it("should transfer the 1% of msg.value to treasury", async () => {
            const treasuryBalanceBefore = await wBera.balanceOf(treasury.address);
            const sellAmount = ethers.utils.parseEther("10000");

            const tx = await expVault
                .connect(user1Signer)
                .sell(token.address, sellAmount, ethers.utils.parseEther("0.0001"), ethers.constants.AddressZero, false);
            const receipt = await tx.wait();
            const tradeEvent = receipt.events?.find((x: any) => x.event === "Trade");
            const baseAmount = tradeEvent.args.baseAmount;

            const treasuryBalanceAfter = await wBera.balanceOf(treasury.address);
            // increase baseAmount by 1%
            const grossBaseAmount = baseAmount.add(baseAmount.div(100));
            const tradingFee = await feeManager.quoteTradingFee(grossBaseAmount);

            // TODO - Check: Test ignoring rounding errors
            // expect(treasuryBalanceAfter.sub(treasuryBalanceBefore)).to.be.eq(tradingFee);
        });

        it("should transfer the referral fee, and a lower trading fee", async () => {
            expect(await referralManager.getReferralRewardFor(ownerSigner.address, wBera.address)).to.be.equal(0);

            const treasuryBalanceBefore = await wBera.balanceOf(treasury.address);
            const sellAmount = ethers.utils.parseEther("10000");

            await expVault
                .connect(user1Signer)
                .sell(token.address, sellAmount, ethers.utils.parseEther("0.0001"), ethers.constants.AddressZero, false);

            const treasuryBalanceAfter = await wBera.balanceOf(treasury.address);
            const tradingFee = await feeManager.quoteTradingFee(sellAmount);

            // Calculate referral fee
            const refUserBps = await referralManager.getReferralBpsFor(user1Signer.address);
            const referralFee = tradingFee.mul(refUserBps).div(10000);

            // TODO - Check: Test ignoring rounding errors
            // expect(await referralManager.getReferralRewardFor(ownerSigner.address, wBera.address)).to.be.equal(referralFee);
            // expect(treasuryBalanceAfter.sub(treasuryBalanceBefore)).to.be.equal(tradingFee.sub(referralFee));
        });

        it("should not collect a referral fee if trading fee is 0", async () => {
            await feeManager.connect(ownerSigner).setTradingFeeBps(0);
            const treasuryBalanceBefore = await wBera.balanceOf(treasury.address);
            await expVault
                .connect(user1Signer)
                .sell(token.address, ethers.utils.parseEther("10000"), ethers.utils.parseEther("0.0001"), ethers.constants.AddressZero, false);
            const treasuryBalanceAfter = await wBera.balanceOf(treasury.address);

            expect(await referralManager.getReferralRewardFor(ownerSigner.address, wBera.address)).to.be.equal(0);
            expect(treasuryBalanceAfter.sub(treasuryBalanceBefore)).to.be.equal(0);
        });
        it("should transfer quote tokens from the user", async () => {
            const userBalanceBefore = await token.balanceOf(user1Signer.address);
            const amountToSell = ethers.utils.parseEther("10000");
            await expVault.connect(user1Signer).sell(token.address, amountToSell, ethers.utils.parseEther("0.0001"), ownerSigner.address, false);
            const userBalanceAfter = await token.balanceOf(user1Signer.address);
            expect(await userBalanceBefore.sub(userBalanceAfter)).to.be.equal(amountToSell);
        });
        it("should transfer base tokens to the user", async () => {
            const userBalanceBefore = await wBera.balanceOf(user1Signer.address);
            await expVault
                .connect(user1Signer)
                .sell(token.address, ethers.utils.parseEther("10000"), ethers.utils.parseEther("0.0001"), ownerSigner.address, false);
            const userBalanceAfter = await wBera.balanceOf(user1Signer.address);
            expect(await userBalanceAfter.sub(userBalanceBefore)).to.be.greaterThan(userBalanceBefore);
        });
        it("should revert if user wants to sell less than 0.001 token", async () => {
            await expect(
                expVault.sell(token.address, ethers.utils.parseEther("0.0001"), 0, ethers.constants.AddressZero, false)
            ).to.be.revertedWithCustomError(expVault, "BuzzVault_InvalidMinTokenAmount");
        });
        it("should emit a trade event", async () => {
            const userTokenBalance = await token.balanceOf(user1Signer.address);
            await token.connect(user1Signer).approve(expVault.address, userTokenBalance);
            await expect(expVault.connect(user1Signer).sell(token.address, userTokenBalance, 0, ethers.constants.AddressZero, false))
                .to.emit(expVault, "Trade")
                .withArgs(
                    user1Signer.address,
                    token.address,
                    wBera.address,
                    userTokenBalance,
                    anyValue,
                    anyValue,
                    anyValue,
                    anyValue,
                    anyValue,
                    anyValue,
                    anyValue,
                    false
                );
        });
        it("should unwrap the wrapped bera", async () => {
            const amountToSell = ethers.utils.parseEther("100");
            await token.connect(user1Signer).approve(expVault.address, amountToSell);
            expect(await await expVault.connect(user1Signer).sell(token.address, amountToSell, 0, ethers.constants.AddressZero, true)).to.emit(
                expVault,
                "Trade"
            );
            // TODO: Calculate eth transfer amount
        });
        it("should increase the tokenBalance in the vault", async () => {
            const tokenInfoBefore = await expVault.tokenInfo(token.address);
            const userTokenBalance = await token.balanceOf(user1Signer.address);
            await token.connect(user1Signer).approve(expVault.address, userTokenBalance);
            await expVault.connect(user1Signer).sell(token.address, userTokenBalance, 0, ethers.constants.AddressZero, false);
            const tokenInfoAfter = await expVault.tokenInfo(token.address);

            expect(tokenInfoAfter[2]).to.be.equal(tokenInfoBefore[2].add(userTokenBalance));
        });
    });
});
