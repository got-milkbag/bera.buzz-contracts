import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

describe("TokenVesting", function () {
  let Token: any;
  let testToken: Contract;
  let TokenVesting: any;
  let owner: SignerWithAddress;
  let addr1: SignerWithAddress;
  let addr2: SignerWithAddress;
  let addrs: SignerWithAddress[];

  before(async function () {
    Token = await ethers.getContractFactory("Token");
    TokenVesting = await ethers.getContractFactory("MockTokenVesting");
  });
  beforeEach(async function () {
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
    testToken = await Token.deploy("Test Token", "TT", 1000000);
    await testToken.deployed();
  });

  describe("Vesting", function () {
    it("Should assign the total supply of tokens to the owner", async function () {
      const ownerBalance = await testToken.balanceOf(owner.address);
      expect(await testToken.totalSupply()).to.equal(ownerBalance);
    });

    it("Should vest tokens gradually", async function () {
      // deploy vesting contract
      const tokenVesting = await TokenVesting.deploy();
      await tokenVesting.deployed();

      // approve tokens to vesting contract
      await expect(testToken.approve(tokenVesting.address, 1000))
        .to.emit(testToken, "Approval")
        .withArgs(owner.address, tokenVesting.address, 1000);
      const vestingContractBalance = await testToken.balanceOf(
        tokenVesting.address
      );

      const baseTime = 1622551248;
      const beneficiary = addr1;
      const startTime = baseTime;
      const cliff = 0;
      const duration = 1000;
      const slicePeriodSeconds = 1;
      const amount = 100;

      // create new vesting schedule
      await tokenVesting.createVestingSchedule(
        beneficiary.address,
        testToken.address,
        startTime,
        cliff,
        duration,
        slicePeriodSeconds,
        amount
      );
      expect(await tokenVesting.getVestingSchedulesCount()).to.be.equal(1);
      expect(
        await tokenVesting.getVestingSchedulesCountByBeneficiary(
          beneficiary.address
        )
      ).to.be.equal(1);

      // compute vesting schedule id
      const vestingScheduleId =
        await tokenVesting.computeVestingScheduleIdForAddressAndIndex(
          beneficiary.address,
          0
        );

      // check that vested amount is 0
      expect(
        await tokenVesting.computeReleasableAmount(testToken.address, vestingScheduleId)
      ).to.be.equal(0);

      // set time to half the vesting period
      const halfTime = baseTime + duration / 2;
      await tokenVesting.setCurrentTime(halfTime);

      // check that vested amount is half the total amount to vest
      expect(
        await tokenVesting
          .connect(beneficiary)
          .computeReleasableAmount(testToken.address, vestingScheduleId)
      ).to.be.equal(50);

      // check that only beneficiary can try to release vested tokens
      await expect(
        tokenVesting.connect(addr2).release(testToken.address, vestingScheduleId)
      ).to.be.revertedWith(
        "TokenVesting: only beneficiary can release vested tokens"
      );

      // release tokens and check that a Transfer event is emitted with a value of 50
      await expect(
        tokenVesting.connect(beneficiary).release(testToken.address, vestingScheduleId)
      )
        .to.emit(testToken, "Transfer")
        .withArgs(tokenVesting.address, beneficiary.address, 50);

      // check that the vested amount is now 0
      expect(
        await tokenVesting
          .connect(beneficiary)
          .computeReleasableAmount(testToken.address, vestingScheduleId)
      ).to.be.equal(0);
      let vestingSchedule = await tokenVesting.getVestingSchedule(
        testToken.address,
        vestingScheduleId
      );

      // check that the released amount is 50
      expect(vestingSchedule.released).to.be.equal(50);

      // set current time after the end of the vesting period
      await tokenVesting.setCurrentTime(baseTime + duration + 1);

      // check that the vested amount is 50
      expect(
        await tokenVesting
          .connect(beneficiary)
          .computeReleasableAmount(testToken.address, vestingScheduleId)
      ).to.be.equal(50);

      // beneficiary release vested tokens (and check for Release event)
      await expect(
        tokenVesting.connect(beneficiary).release(testToken.address, vestingScheduleId)
      )
        .to.emit(tokenVesting, "TokensReleased")
        .withArgs(vestingScheduleId, beneficiary.address, 50);

      vestingSchedule = await tokenVesting.getVestingSchedule(
        testToken.address,
        vestingScheduleId
      );

      // check that the number of released tokens is 100
      expect(vestingSchedule.released).to.be.equal(100);

      // check that the vested amount is 0
      expect(
        await tokenVesting
          .connect(beneficiary)
          .computeReleasableAmount(testToken.address, vestingScheduleId)
      ).to.be.equal(0);

      /*
       * TEST SUMMARY
       * deploy vesting contract
       * approve tokens to vesting contract
       * create new vesting schedule (100 tokens)
       * check that vested amount is 0
       * set time to half the vesting period
       * check that vested amount is half the total amount to vest (50 tokens)
       * check that only beneficiary can try to release vested tokens
       * release 50 tokens and check that a Transfer event is emitted with a value of 50
       * check that the released amount is 50
       * check that the vested amount is now 0
       * set current time after the end of the vesting period
       * check that the vested amount is 50 (100 - 50 released tokens)
       * release all vested tokens (50)
       * check that the number of released tokens is 100
       * check that the vested amount is 0
       */
    });

    it("Should compute vesting schedule index", async function () {
      const tokenVesting = await TokenVesting.deploy();
      await tokenVesting.deployed();
      const expectedVestingScheduleId =
        "0xa279197a1d7a4b7398aa0248e95b8fcc6cdfb43220ade05d01add9c5468ea097";
      expect(
        (
          await tokenVesting.computeVestingScheduleIdForAddressAndIndex(
            addr1.address,
            0
          )
        ).toString()
      ).to.equal(expectedVestingScheduleId);
      expect(
        (
          await tokenVesting.computeNextVestingScheduleIdForHolder(
            addr1.address
          )
        ).toString()
      ).to.equal(expectedVestingScheduleId);
    });

    it("Should check input parameters for createVestingSchedule method", async function () {
      const tokenVesting = await TokenVesting.deploy();
      await tokenVesting.deployed();
      await testToken.approve(tokenVesting.address, 1000);
      const time = Date.now();
      await expect(
        tokenVesting.createVestingSchedule(
          addr1.address,
          testToken.address,
          time,
          0,
          0,
          1,
          1
        )
      ).to.be.revertedWith("TokenVesting: duration must be > 0");
      await expect(
        tokenVesting.createVestingSchedule(
          addr1.address,
          testToken.address,
          time,
          0,
          1,
          0,
          1
        )
      ).to.be.revertedWith("TokenVesting: slicePeriodSeconds must be >= 1");
      await expect(
        tokenVesting.createVestingSchedule(
          addr1.address,
          testToken.address,
          time,
          0,
          1,
          1,
          0
        )
      ).to.be.revertedWith("TokenVesting: amount must be > 0");
      await expect(
        tokenVesting.createVestingSchedule(
          ethers.constants.AddressZero,
          testToken.address,
          time,
          1,
          1,
          1,
          1
        )
      ).to.be.revertedWith("TokenVesting: beneficiary cannot be the zero address");
      await expect(
        tokenVesting.createVestingSchedule(
          addr1.address,
          ethers.constants.AddressZero,
          time,
          1,
          1,
          1,
          1
        )
      ).to.be.revertedWith("TokenVesting: token cannot be the zero address");
    });

    it("Should not release tokens before cliff", async function () {
      // deploy vesting contract
      const tokenVesting = await TokenVesting.deploy();
      await tokenVesting.deployed();

      // approve tokens to vesting contract
      await expect(testToken.approve(tokenVesting.address, 1000))
        .to.emit(testToken, "Approval")
        .withArgs(owner.address, tokenVesting.address, 1000);

      const baseTime = 1622551248;
      const beneficiary = addr1;
      const startTime = baseTime;
      const cliff = 100; // Set a non-zero cliff duration
      const duration = 1000;
      const slicePeriodSeconds = 1;
      const amount = 100;

      // compute vesting schedule id
      const vestingScheduleId =
      await tokenVesting.computeVestingScheduleIdForAddressAndIndex(
        beneficiary.address,
        0
      );

      // create new vesting schedule (and check event emission)
      await expect(tokenVesting.createVestingSchedule(
        beneficiary.address,
        testToken.address,
        startTime,
        cliff,
        duration,
        slicePeriodSeconds,
        amount
      )).to.emit(tokenVesting, "VestingScheduleCreated")
        .withArgs(
          vestingScheduleId, 
          beneficiary.address,
          testToken.address,
          startTime + cliff,
          startTime,
          duration,
          slicePeriodSeconds,
          amount
        );

      // check that vested amount is 0 before cliff
      expect(
        await tokenVesting.computeReleasableAmount(testToken.address, vestingScheduleId)
      ).to.be.equal(0);

      // set time to just before the cliff
      const justBeforeCliff = baseTime + cliff - 1;
      await tokenVesting.setCurrentTime(justBeforeCliff);

      // check that vested amount is still 0 just before the cliff
      expect(
        await tokenVesting.computeReleasableAmount(testToken.address, vestingScheduleId)
      ).to.be.equal(0);

      // set time to the cliff
      await tokenVesting.setCurrentTime(baseTime + cliff + 200);

      // check that vested amount is greater than 0 at the cliff
      expect(
        await tokenVesting.computeReleasableAmount(testToken.address, vestingScheduleId)
      ).to.be.equal(20);
    });

    it("Should vest tokens correctly with a 6-months cliff and 12-months duration", async function () {
      // deploy vesting contract
      const tokenVesting = await TokenVesting.deploy();
      await tokenVesting.deployed();

      // approve tokens to vesting contract
      await expect(testToken.approve(tokenVesting.address, 1000))
        .to.emit(testToken, "Approval")
        .withArgs(owner.address, tokenVesting.address, 1000);

      const baseTime = 1622551248; // June 1, 2021
      const beneficiary = addr1;
      const startTime = baseTime;
      const cliff = 15552000; // 6 months in seconds
      const duration = 31536000; // 12 months in seconds
      const slicePeriodSeconds = 2592000; // 1 month in seconds
      const amount = 1000;

      // create new vesting schedule
      await tokenVesting.createVestingSchedule(
        beneficiary.address,
        testToken.address,
        startTime,
        cliff,
        duration,
        slicePeriodSeconds,
        amount
      );

      // compute vesting schedule id
      const vestingScheduleId =
        await tokenVesting.computeVestingScheduleIdForAddressAndIndex(
          beneficiary.address,
          0
        );

      // check that vested amount is 0 before cliff
      expect(
        await tokenVesting.computeReleasableAmount(testToken.address, vestingScheduleId)
      ).to.be.equal(0);

      // set time to just before the cliff (5 months)
      const justBeforeCliff = baseTime + cliff - 2592000;
      await tokenVesting.setCurrentTime(justBeforeCliff);

      // check that vested amount is still 0 just before the cliff
      expect(
        await tokenVesting.computeReleasableAmount(testToken.address, vestingScheduleId)
      ).to.be.equal(0);

      // set time to the cliff (6 months)
      await tokenVesting.setCurrentTime(baseTime + cliff);

      // check that vested amount is equal to the total amount at the cliff
      expect(
        await tokenVesting.computeReleasableAmount(testToken.address, vestingScheduleId)
      ).to.be.equal(0);

      // set time to halfway through the vesting period (12 months)
      const halfwayThrough = baseTime + cliff + duration / 2;
      await tokenVesting.setCurrentTime(halfwayThrough);

      // check that vested amount is greater than 0
      expect(
        await tokenVesting.computeReleasableAmount(testToken.address, vestingScheduleId)
      ).to.be.gt(400);

      // set time to the end of the vesting period (18 months)
      const endOfVesting = baseTime + cliff + duration;
      await tokenVesting.setCurrentTime(endOfVesting);

      // check that vested amount is equal to the total amount
      expect(
        await tokenVesting.computeReleasableAmount(testToken.address, vestingScheduleId)
      ).to.be.equal(amount);
    });

  });
});