const { assert, expect } = require("chai");
const { debug, deployChef, returnChef, getGlobalInfo, viewPoolInfo, viewLpToken, viewRewarder, getPositionInfo,
  getPoolCount, add, set, pendingRelic, massUpdatePools, updatePool, createNewPositionAndDeposit, createNewPosition,
  deposit, withdraw, harvest, withdrawAndHarvest, emrgencyWithdraw, curved } = require("../src/Reliquary.js");

let owner, alice, bob;

let zeroAddress = "0x0000000000000000000000000000000000000000";

describe("Reliquary", function () {
  beforeEach(async function () {
    [owner, alice, bob] = await ethers.getSigners();

    this.ERC20Mock = await ethers.getContractFactory("ERC20Mock");
    const Relic = await ethers.getContractFactory("Relic");
    this.relic = await Relic.deploy("Relic", "RELIC");
    this.lp = await this.ERC20Mock.deploy("LP Token", "LPT", owner.address, ethers.utils.parseEther("1000"));

    const EighthRoot = await ethers.getContractFactory("EighthRoot");
    this.curve = await EighthRoot.deploy();

    this.chef = await deployChef(this.relic.address);
    await this.relic.mint(this.chef.address, ethers.utils.parseEther("100000000"));
    //const Rewarder = await ethers.getContractFactory("RewarderMock");
    //this.rewarder = await Rewarder.deploy(1, this.relic.address, this.chef.address);
  })

  describe("PoolLength", function () {
    it("PoolLength should execute", async function () {
      await add(this.chef.address, 100, this.lp.address, zeroAddress, this.curve.address);
      expect(await getPoolCount(this.chef.address)).to.be.equal(1);
    })
  })

  describe("Set", function () {
    it("Should emit event LogSetPool", async function () {
      await add(this.chef.address, 100, this.lp.address, zeroAddress, this.curve.address);
      await expect(this.chef.set(0, 100, zeroAddress, this.curve.address, false, false)).to.emit(this.chef, "LogSetPool");
      await expect(this.chef.set(0, 100, this.relic.address, this.curve.address, true, false)).to.emit(this.chef, "LogSetPool").
        withArgs(0, 100, this.relic.address, this.curve.address);
    })

    it("Should revert if invalid pool", async function () {
      await expect(this.chef.set(0, 100, zeroAddress, this.curve.address, false, false)).to.be.reverted;
    })
  })

  describe("PendingRelic", function () {
    // take into account curve
    it("PendingRelic should equal ExpectedRelic", async function () {
      await add(this.chef.address, 1, this.lp.address, zeroAddress, this.curve.address);
      await this.lp.approve(this.chef.address, ethers.utils.parseEther("1000"));
      await this.chef.createPositionAndDeposit(alice.address, 0, ethers.utils.parseEther("1"));
      await network.provider.send("evm_increaseTime", [31557600]);
      await network.provider.send("evm_mine");
      await this.chef.updatePool(0);
      await network.provider.send("evm_mine");
      const firstOwnedToken = await this.chef.tokenOfOwnerByIndex(alice.address, 0);
      const pendingRelic = await this.chef.pendingRelic(firstOwnedToken);
      await this.chef.harvest(firstOwnedToken);
      const balance = await this.relic.balanceOf(alice.address);
      expect(pendingRelic).to.equal(balance);
    })
    it("When block is lastRewardBlock", async function () {})
  })

  describe("MassUpdatePools", function () {
    it("Should call updatePool", async function () {
      await add(this.chef.address, 1, this.lp.address, zeroAddress, this.curve.address);
      await network.provider.send("evm_mine");
      await this.chef.massUpdatePools([0]);
    })
    it("Updating invalid pools should fail", async function () {
      await expect(this.chef.massUpdatePools([0, 1000, 10000])).to.be.reverted;
    })
  })

  describe("Add", function () {
    it("Should add pool with reward token multiplier", async function () {
      await expect(this.chef.add(10, this.lp.address, zeroAddress, this.curve.address))
        .to.emit(this.chef, "LogPoolAddition")
        .withArgs(0, 10, this.lp.address, zeroAddress, this.curve.address);
    })
  })

  describe("UpdatePool", function () {
    it("Should emit event LogUpdatePool", async function () {
      await add(this.chef.address, 1, this.lp.address, zeroAddress, this.curve.address);
      await network.provider.send("evm_mine");
      await expect(this.chef.updatePool(0))
        .to.emit(this.chef, "LogUpdatePool")
        .withArgs(
          0,
          (await this.chef.poolInfo(0)).lastRewardTime,
          await this.lp.balanceOf(this.chef.address),
          (await this.chef.poolInfo(0)).accRelicPerShare
        )
    })
  })

  // ensure global curve can't be affected
  describe("Deposit", function () {
    it("Depositing 0 amount", async function () {})
    it("Depositing into non-existent pool should fail", async function () {})
  })
/*
  describe("Withdraw", function () {
    it("Withdraw 0 amount", async function () {})
  })

  describe("Harvest", function () {
    // take into account curve
    it("Should give back the correct amount of RELIC and reward", async function () {})
    it("Harvest with empty user balance", async function () {})
  })

  describe("EmergencyWithdraw", function () {
    it("Should emit event EmergencyWithdraw", async function () {})
  })*/
})
