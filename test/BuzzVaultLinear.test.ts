import {expect} from "chai";
import {ethers} from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import * as helpers from "@nomicfoundation/hardhat-network-helpers";
import {BigNumber, Contract} from "ethers";

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
    let bexPriceDecoder: Contract;

    const directRefFeeBps = 1500; // 15% of protocol fee
    const indirectRefFeeBps = 100; // fixed 1%
    const payoutThreshold = 0;
    let validUntil: number;

    beforeEach(async () => {
        validUntil = (await helpers.time.latest()) + ONE_YEAR_IN_SECS;

        [ownerSigner, user1Signer, user2Signer, feeRecipientSigner] = await ethers.getSigners();
        feeRecipient = feeRecipientSigner.address;

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
        factory = await Factory.connect(ownerSigner).deploy(eventTracker.address);

        // Deploy Linear Vault
        const Vault = await ethers.getContractFactory("BuzzVaultLinear");
        vault = await Vault.connect(ownerSigner).deploy(
            feeRecipient,
            factory.address,
            referralManager.address,
            eventTracker.address,
            bexPriceDecoder.address
        );

        // Deploy Exponential Vault
        const ExpVault = await ethers.getContractFactory("BuzzVaultExponential");
        expVault = await ExpVault.connect(ownerSigner).deploy(
            feeRecipient,
            factory.address,
            referralManager.address,
            eventTracker.address,
            bexPriceDecoder.address
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
        const tx = await factory.createToken("TEST", "TEST", "Test token is the best", "0x0", vault.address);
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
        it("should revert if msg.value is zero", async () => {
            await expect(
                vault.buy(token.address, ethers.utils.parseEther("1"), ethers.constants.AddressZero, {value: 0})
            ).to.be.revertedWithCustomError(vault, "BuzzVault_InvalidAmount");
        });
        it("should revert if token doesn't exist", async () => {
            await expect(
                vault.buy(ownerSigner.address, ethers.utils.parseEther("1"), ethers.constants.AddressZero, {value: ethers.utils.parseEther("0.1")})
            ).to.be.revertedWithCustomError(vault, "BuzzVault_UnknownToken");
        });
        it("should set a referral if one is provided", async () => {
            await vault
                .connect(user1Signer)
                .buy(token.address, ethers.utils.parseEther("0.001"), ownerSigner.address, {value: ethers.utils.parseEther("0.1")});
            expect(await referralManager.referredBy(user1Signer.address)).to.be.equal(ownerSigner.address);
        });
        it("should emit a trade event", async () => {
            await expect(
                vault
                    .connect(user1Signer)
                    .buy(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, {value: ethers.utils.parseEther("0.1")})
            ).to.emit(eventTracker, "trade");
        });
        it("should transfer the 1% of msg.value to feeRecipient", async () => {
            const feeRecipientBalanceBefore = await ethers.provider.getBalance(feeRecipient);
            const msgValue = ethers.utils.parseEther("0.1");
            await vault.connect(user1Signer).buy(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, {value: msgValue});
            const feeRecipientBalanceAfter = await ethers.provider.getBalance(feeRecipient);
            expect(feeRecipientBalanceAfter.sub(feeRecipientBalanceBefore)).to.be.equal(msgValue.div(100)); // fee is 1%
        });
        // Add more tests
        it("should increase the BeraAmount and decrease the tokenBalance after the buy", async () => {
            const tokenInfoBefore = await vault.tokenInfo(token.address);
            const msgValue = ethers.utils.parseEther("0.01");
            await vault.connect(user1Signer).buy(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, {value: msgValue});
            const tokenInfoAfter = await vault.tokenInfo(token.address);
            const userTokenBalance = await token.balanceOf(user1Signer.address);
            const msgValueAfterFee = msgValue.sub(msgValue.div(100));

            let pricePerToken = calculateTokenPrice(msgValue, userTokenBalance);
            console.log("Price per token in Bera: ", pricePerToken);
            console.log("Bera balance before: ", userTokenBalance);
            // get market cap
            let marketCap = await vault.getMarketCapFor(token.address);
            console.log("Market cap: ", marketCap);
            // check balances
            expect(tokenInfoAfter[0]).to.be.equal(tokenInfoBefore[0].sub(userTokenBalance));
            expect(tokenInfoAfter[1]).to.be.equal(tokenInfoBefore[1].add(msgValueAfterFee));
            console.log("buy again");
            await vault.connect(user1Signer).buy(token.address, ethers.utils.parseEther("0.001"), ethers.constants.AddressZero, {value: msgValue});
            console.log("user's new balance: ", await token.balanceOf(user1Signer.address));
            // calculate sale price
            pricePerToken = calculateTokenPrice(msgValue, userTokenBalance);
            console.log("Price per token in Bera: ", pricePerToken);

            // get market cap
            marketCap = await vault.getMarketCapFor(token.address);
            console.log("Market cap: ", marketCap);
            // sell tokens
            const sellAmount = await token.balanceOf(user1Signer.address);
            await token.connect(user1Signer).approve(vault.address, sellAmount);
            await vault.connect(user1Signer).sell(token.address, sellAmount, 0, ethers.constants.AddressZero);
        });
    });
});
