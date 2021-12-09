const { assert, expect } = require("chai");
const { debug, deployChef, returnChef, getGlobalInfo, viewPoolInfo, viewLpToken, viewRewarder, getPositionInfo,
  getPoolCount, add, set, pendingRelic, massUpdatePools, updatePool, createNewPositionAndDeposit, createNewPosition,
  deposit, withdraw, harvest, withdrawAndHarvest, emrgencyWithdraw, curved } = require("../src/Reliquary.js");

let owner, alice, bob;

describe("Reliquary", function () {
  beforeEach(async function () {
    [owner, alice, bob] = await ethers.getSigners();

    const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
    const Relic = await ethers.getContractFactory("Relic");
    this.relic = await Relic.deploy("Relic", "RELIC");
    this.lp = await ERC20Mock.deploy("LP Token", "LPT", owner.address, ethers.utils.parseEther("1000"));

    const EighthRoot = await ethers.getContractFactory("EighthRoot");
    this.curve = await EighthRoot.deploy();

    this.chef = await deployChef(this.relic.address);
    await this.relic.mint(this.chef.address, ethers.utils.parseEther("100000000"));
    const Rewarder = await ethers.getContractFactory("RewarderMock");
    this.rewarder = await Rewarder.deploy(1, this.relic.address, this.chef.address);
  })

  describe("PoolLength", function () {
    it("PoolLength should execute", async function () {
      await add(this.chef.address, 100, this.lp.address, this.rewarder.address, this.curve.address);
      expect(await getPoolCount(this.chef.address)).to.be.equal(1);
    })
  })

  describe("Set", function () {
    it("Should emit event LogSetPool", async function () {
      await add(this.chef.address, 100, this.lp.address, this.rewarder.address, this.curve.address);
      await expect(this.chef.set(0, 100, this.rewarder.address, this.curve.address, false, false)).to.emit(this.chef, "LogSetPool");
      await expect(this.chef.set(0, 100, this.relic.address, this.curve.address, true, false)).to.emit(this.chef, "LogSetPool").
        withArgs(0, 100, this.relic.address, this.curve.address);
    })

    it("Should revert if invalid pool", async function () {
      await expect(this.chef.set(0, 100, this.rewarder.address, this.curve.address, false, false)).to.be.reverted;
    })
  })

  describe("PendingRelic", function () {
    // take into account curve
    it("PendingRelic should equal ExpectedRelic", async function () {
      await add(this.chef.address, 100, this.lp.address, this.rewarder.address, this.curve.address);
      await this.lp.approve(this.chef.address, ethers.utils.parseEther("1000"));
      let log = await this.chef.createPositionAndDeposit(alice.address, 0, ethers.utils.parseEther("1000"));
      await ethers.provider.send("evm_increaseTime", [31557600]);
      await ethers.provider.send("evm_mine", []);
      let log2 = await this.chef.updatePool(0);
      await ethers.provider.send("evm_mine", []);
      let pendingRelic = await this.chef.pendingRelic(0, 0);
      console.log(pendingRelic.toString());
    })
    it("When block is lastRewardBlock", async function () {})
  })
/*
  describe("MassUpdatePools", function () {
    it("Should call updatePool", async function () {})
    it("Updating invalid pools should fail", async function () {})
  })

  describe("Add", function () {
    it("Should add pool with reward token multiplier", async function () {})
  })

  describe("UpdatePool", function () {
    it("Should emit event LogUpdatePool", async function () {})
  })

  // ensure global curve can't be affected
  describe("Deposit", function () {
    it("Depositing 0 amount", async function () {})
    it("Depositing into non-existent pool should fail", async function () {})
  })

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
