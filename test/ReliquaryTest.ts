const { assert, expect } = require("chai");
const { debug, deployChef, returnChef, getGlobalInfo, viewPoolInfo, viewLpToken, viewRewarder, getPositionInfo,
  getPoolCount, add, set, pendingRelic, massUpdatePools, updatePool, createNewPositionAndDeposit, createNewPosition,
  deposit, withdraw, harvest, withdrawAndHarvest, emrgencyWithdraw, curved } = require("../src/Reliquary.js");

describe("Reliquary", function () {
  describe("Init", function () {})

  describe("PoolLength", function () {
    it("PoolLength should execute", async function () {})
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
