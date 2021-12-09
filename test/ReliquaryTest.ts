const { assert, expect } = require("chai");
const { debug, deployChef, returnChef, getGlobalInfo, viewPoolInfo, viewLpToken, viewRewarder, getPositionInfo,
  getPoolCount, add, set, pendingRelic, massUpdatePools, updatePool, createNewPositionAndDeposit, createNewPosition,
  deposit, withdraw, harvest, withdrawAndHarvest, emrgencyWithdraw, curved } = require("../src/Reliquary.js");

describe("Reliquary", function () {
  beforeEach(async function () {
    let [owner, alice, bob] = await ethers.getSigners();

    const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
    this.relic = await ERC20Mock.deploy("Relic", "RELIC", owner.address, 1000000);
    this.lp = await ERC20Mock.deploy("LP Token", "LPT", owner.address, 1000000);

    const EighthRoot = await ethers.getContractFactory("EighthRoot");
    this.curve = await EighthRoot.deploy();

    this.chef = await deployChef(this.relic.address);
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
    it("Should emit event LogSetPool", async function () {})
    it("Should revert if invalid pool", async function () {})
  })

  describe("PendingRelic", function () {
    // take into account curve
    it("PendingRelic should equal ExpectedRelic", async function () {})
    it("When block is lastRewardBlock", async function () {})
  })

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
  })
})
