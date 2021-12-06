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

async function returnChef(chefAddress) {
  debugSwitch ? debug(arguments);
  let Chef2 = await ethers.getContractFactory("MasterChefV2");
  let chef = await Chef2.attach(chefAddress);
  return chef;
}

async function getGlobalInfo(chefAddress) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let globalInfo = {
    totalAllocPoint: await chef.totalAllocPoint(),
    relicPerBlock: await chef.RELIC_PER_BLOCK(),
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

async function viewLpTokens(chefAddress, pid) {
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

async function getUserInfo(chefAddress, pid, userAddress) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let userInfo = await chef.userInfo(pid, userAddress);
  return userInfo;
}

async function getPoolCount(chefAddress) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let poolLength = await chef.poolLength();
  return poolLength;
}

async function add(chefAddress, allocPoint, lpToken, rewarder) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let tx = await chef.add(allocPoint, lpToken, rewarder);
  let receipt = await tx.wait();
  return receipt;
}

async function set(chefAddress, pid, rewarder, overwrite) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let tx = await chef.set(pic, rewarder, overwrite);
  let receipt = await tx.wait();
  return receipt;
}

async function pendingSushi(chefAddress, pid, userAddress) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);
  let tx = await chef.pendingRelic
}

async function massUpdatePools(chefAddress, pidArray) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);

}

async function sushiPerBlock(chefAddress) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);

}

async function updatePool(chefAddress, pid) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);

}

async function deposit(chefAddress, pid, amount, depositTo) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);

}

async function withdraw(chefAddress, pid, amount, withdrawTo) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);

}

async function harvest(chefAddress, pid, withdrawAndRewardsTo) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);

}

async function withdrawAndHarvest(chefAddress, pid, rewardsTo) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);

}

async function emergencyWithdraw(chefAddress, pid, withdrawTo) {
  debugSwitch ? debug(arguments);
  let chef = await returnChef(chefAddress);

}
