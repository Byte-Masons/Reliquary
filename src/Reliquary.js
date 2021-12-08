const tokens = require("../tokens.json");
const reaper = require("./ReaperSDK.js");

async function deployChef()

let debugSwitch = false;

function debug(arguments) {
  let argumentTypes;
  for(let i=0; i<arguments.length; i++) {
    argumentTypes.push(typeof arguments[i]);
  }
  return argumentTypes;
}

async function deployChef(relicAddress) {
  debugSwitch ? debug(arguments);
  let Reliquary = await ethers.getContractFactory("Reliquary");
  let chef = await Reliquary.deploy(relicAddress);
  return chef;
}

async function returnChef(chefAddress) {
  debugSwitch ? debug(arguments);
  let Reliquary = await ethers.getContractFactory("Reliquary");
  let chef = await Chef2.attach(chefAddress);
  return chef;
}

async function getGlobalInfo(chefAddress) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let globalInfo = {
    totalAllocPoint: await chef.totalAllocPoint(),
    relicPerBlock: await chef.BASE_RELIC_PER_BLOCK(),
    chefToken: await chef.RELIC();
  }
  return globalInfo;
}

async function viewPoolInfo(chefAddress, pid) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let poolInfo = await chef.poolInfo(pid);
  return poolInfo;
}

async function viewLpToken(chefAddress, pid) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let lpToken = await chef.lpToken(pid);
  return lpToken;
}

async function viewRewarder(chefAddress, pid) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let rewarder = await chef.rewarder(pid);
  return rewarder;
}

async function getPositionInfo(chefAddress, pid, positionId) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let userInfo = await chef.userInfo(pid, positionId);
  return userInfo;
}

async function getPoolCount(chefAddress) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let poolLength = await chef.poolLength();
  return poolLength;
}

async function add(chefAddress, allocPoint, lpToken, rewarder, curve) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let tx = await chef.add(allocPoint, lpToken, rewarder, curve);
  let receipt = await tx.wait();
  return receipt;
}

async function set(chefAddress, pid, rewarder, curve, overwriteRewarder, overwriteCurve) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let tx = await chef.set(pic, rewarder, overwrite);
  let receipt = await tx.wait();
  return receipt;
}

async function pendingRelic(chefAddress, pid, positionId) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let pending = await chef.pendingRelic(pid, positoinId);
  return pending;
}

async function massUpdatePools(chefAddress, pids) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let tx = await chef.massUpdatePools(pids)
  let receipt = await tx.wait();
  return receipt;
}

async function updatePool(chefAddress, pid) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let pool = await chef.updatePool(pid);
  await pool.wait();
  return pool;
}

async function createNewPositionAndDeposit(chefAddress, to, pid, amount) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let id = await chef.createNewPositionAndDeposit(to, pid, amount);
  await id.wait();
  return id;
}

async function createNewPosition(chefAddress, to, pid) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let id = await chef.createNewPosition(to, pid, amount);
  await id.wait();
  return id;
}

async function deposit(chefAddress, pid, amount, positionId) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let tx = await chef.deposit(pid, amount, positionId);
  let receipt = await tx.wait();
  return receipt;
}

async function withdraw(chefAddress, pid, amount, positionId) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let tx = await chef.withdraw(pid, amount, positionId);
  let receipt = await tx.wait();
  return receipt;
}

async function harvest(chefAddress, pid, positionId) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let tx = await chef.harvest(pid, positionId);
  let receipt = await tx.wait();
  return receipt;
}

async function withdrawAndHarvest(chefAddress, pid, amount, positionId) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let tx = await chef.harvest(pid, amount, positionId);
  let receipt = await tx.wait();
  return receipt;
}

async function emergencyWithdraw(chefAddress, pid, positionId) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let tx = await chef.emergencyWithdraw(pid, positionId);
  let receipt = await tx.wait();
  return receipt;
}

async function curved(chefAddress, positionId, pid) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let curvedValue = await chef.curved(positionId, pid);
  await curvedValue.wait();
  return curvedValue;
}

module.exports = {
  debug,
  deployChef,
  returnChef,
  getGlobalInfo,
  viewPoolInfo,
  viewLpToken,
  viewRewarder,
  getPositionInfo,
  getPoolCount,
  add,
  set,
  pendingRelic,
  massUpdatePools,
  updatePool,
  createNewPositionAndDeposit,
  createNewPosition,
  deposit,
  withdraw,
  harvest,
  withdrawAndHarvest,
  emergencyWithdraw,
  curved
}
