function debug(arguments) {
  let argumentTypes;
  for(let i=0; i<arguments.length; i++) {
    argumentTypes.push(typeof arguments[i]);
  }
  return argumentTypes;
}

async function deployChef(oathAddress) {
  let Reliquary = await ethers.getContractFactory("Reliquary");
  let chef = await Reliquary.deploy(oathAddress);
  return chef;
}

async function returnChef(chefAddress) {
  let Reliquary = await ethers.getContractFactory("Reliquary");
  let chef = await Reliquary.attach(chefAddress);
  return chef;
}

async function getGlobalInfo(chefAddress) {
  let chef = await returnChef(chefAddress);
  let globalInfo = {
    totalAllocPoint: await chef.totalAllocPoint(),
    chefToken: await chef.OATH()
  }
  return globalInfo;
}

async function deployRewarder(multiplier, token, chefAddress) {
  let Rewarder = await ethers.getContractFactory("RewarderMock");
  let rewarder = await Rewarder.deploy(multiplier, token, chefAddress);
  return rewarder;
}

async function deployCurve() {
  let Curve = await ethers.getContractFactory("EighthRoot");
  let curve = await Curve.deploy();
  return curve;
}

async function viewPoolInfo(chefAddress, pid) {
  let chef = await returnChef(chefAddress);
  let poolInfo = await chef.poolInfo(pid);
  let obj = {
    "accOathPerShare": poolInfo[0].toString(),
    "lastRewardTime": poolInfo[1].toString(),
    "allocPoint": poolInfo[2].toString(),
    "averageEntry": poolInfo[3].toString(),
    "curveAddress": poolInfo[4]
  }
  return obj;
}

async function viewLpToken(chefAddress, pid) {
  let chef = await returnChef(chefAddress);
  let lpToken = await chef.lpToken(pid);
  return lpToken;
}

async function viewRewarder(chefAddress, pid) {
  let chef = await returnChef(chefAddress);
  let rewarder = await chef.rewarder(pid);
  return rewarder;
}

async function getPositionInfo(chefAddress, pid, positionId) {
  let chef = await returnChef(chefAddress);
  let userInfo = await chef.positionInfo(pid, positionId);
  return {
    "amount": userInfo[0].toString(),
    "rewardDebt": userInfo[1].toString(),
    "entry": userInfo[2].toString(),
    "exempt": userInfo[3]
  };
}

async function getPoolCount(chefAddress) {
  let chef = await returnChef(chefAddress);
  let poolLength = await chef.poolLength();
  return poolLength;
}

async function add(chefAddress, allocPoint, lpToken, rewarder, curve) {
  let chef = await returnChef(chefAddress);
  let tx = await chef.add(allocPoint, lpToken, rewarder, curve);
  let receipt = await tx.wait();
  return receipt;
}

async function set(chefAddress, pid, rewarder, curve, overwriteRewarder, overwriteCurve) {
  let chef = await returnChef(chefAddress);
  let tx = await chef.set(pic, rewarder, overwrite);
  let receipt = await tx.wait();
  return receipt;
}

async function pendingOath(chefAddress, pid, positionId) {
  let chef = await returnChef(chefAddress);
  let pending = await chef.pendingOath(pid, positionId);
  return pending;
}

async function massUpdatePools(chefAddress, pids) {
  let chef = await returnChef(chefAddress);
  let tx = await chef.massUpdatePools(pids)
  let receipt = await tx.wait();
  return receipt;
}

async function updatePool(chefAddress, pid) {
  let chef = await returnChef(chefAddress);
  let tx = await chef.updatePool(pid);
  let receipt = await tx.wait();
  return receipt;
}

async function createNewPositionAndDeposit(chefAddress, to, pid, amount) {
  let chef = await returnChef(chefAddress);
  let tx = await chef.createPositionAndDeposit(to, pid, amount);
  let receipt = await tx.wait();
  return receipt;
}

async function createNewPosition(chefAddress, to, pid, amount) {
  let chef = await returnChef(chefAddress);
  let id = await chef.createNewPosition(to, pid, amount);
  await id.wait();
  return id;
}

async function deposit(chefAddress, pid, amount, positionId) {
  let chef = await returnChef(chefAddress);
  let tx = await chef.deposit(pid, amount, positionId);
  let receipt = await tx.wait();
  return receipt;
}

async function withdraw(chefAddress, pid, amount, positionId) {
  let chef = await returnChef(chefAddress);
  let tx = await chef.withdraw(pid, amount, positionId);
  let receipt = await tx.wait();
  return receipt;
}

async function harvest(chefAddress, pid, positionId) {
  let chef = await returnChef(chefAddress);
  let tx = await chef.harvest(pid, positionId);
  let receipt = await tx.wait();
  return receipt;
}

async function withdrawAndHarvest(chefAddress, pid, amount, positionId) {
  let chef = await returnChef(chefAddress);
  let tx = await chef.harvest(pid, amount, positionId);
  let receipt = await tx.wait();
  return receipt;
}

async function emergencyWithdraw(chefAddress, pid, positionId) {
  let chef = await returnChef(chefAddress);
  let tx = await chef.emergencyWithdraw(pid, positionId);
  let receipt = await tx.wait();
  return receipt;
}

async function curved(chefAddress, positionId, pid) {
  let chef = await returnChef(chefAddress);
  let curvedValue = await chef.curved(positionId, pid);
  await curvedValue.wait();
  return curvedValue;
}

async function tokenOfOwnerByIndex(chefAddress, ownerAddress, index) {
  let chef = await returnChef(chefAddress);
  let tokenId = await chef.tokenOfOwnerByIndex(ownerAddress, index);
  return tokenId;
}

async function tokenByIndex(chefAddress, index) {
  let chef = await returnChef(chefAddress);
  let tokenId = await chef.tokenByIndex(index);
  return tokenId;
}

async function totalPositions(chefAddress) {
  let chef = await returnChef(chefAddress);
  let supply = chef.totalSupply();
  return supply;
}

module.exports = {
  debug,
  deployChef,
  deployRewarder,
  deployCurve,
  tokenOfOwnerByIndex,
  tokenByIndex,
  totalPositions,
  returnChef,
  getGlobalInfo,
  viewPoolInfo,
  viewLpToken,
  viewRewarder,
  getPositionInfo,
  getPoolCount,
  add,
  set,
  pendingOath,
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
