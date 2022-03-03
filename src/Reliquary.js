function debug(arguments) {
  let argumentTypes;
  for (let i = 0; i < arguments.length; i++) {
    argumentTypes.push(typeof arguments[i]);
  }
  return argumentTypes;
}

async function deployChef(oathAddress, nftDescriptorAddress) {
  let Reliquary = await ethers.getContractFactory('Reliquary');
  let chef = await Reliquary.deploy(oathAddress, nftDescriptorAddress);
  return chef;
}

async function returnChef(chefAddress) {
  let Reliquary = await ethers.getContractFactory('Reliquary');
  let chef = await Reliquary.attach(chefAddress);
  return chef;
}

async function getGlobalInfo(chefAddress) {
  let chef = await returnChef(chefAddress);
  let globalInfo = {
    totalAllocPoint: await chef.totalAllocPoint(),
    chefToken: await chef.OATH(),
  };
  return globalInfo;
}

async function deployNFTDescriptor() {
  let NFTDescriptor = await ethers.getContractFactory('NFTDescriptor');
  let nftDescriptor = await NFTDescriptor.deploy();
  return nftDescriptor;
}

async function deployRewarder(multiplier, token, chefAddress) {
  let Rewarder = await ethers.getContractFactory('RewarderMock');
  let rewarder = await Rewarder.deploy(multiplier, token, chefAddress);
  return rewarder;
}

async function deployCurve() {
  let Curve = await ethers.getContractFactory('EighthRoot');
  let curve = await Curve.deploy();
  return curve;
}

async function viewPoolInfo(chefAddress, pid) {
  let chef = await returnChef(chefAddress);
  let poolInfo = await chef.poolInfo(pid);
  let obj = {
    accOathPerShare: poolInfo[0].toString(),
    lastRewardTime: poolInfo[1].toString(),
    allocPoint: poolInfo[2].toString(),
    averageEntry: poolInfo[3].toString(),
    curveAddress: poolInfo[4],
  };
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

async function getPositionInfo(chefAddress, positionId) {
  let chef = await returnChef(chefAddress);
  let userInfo = await chef.positionForId(positionId);
  return {
    amount: userInfo[0].toString(),
    rewardDebt: userInfo[1].toString(),
    entry: userInfo[2].toString(),
    poolId: userInfo[3].toString(),
  };
}

async function getPoolCount(chefAddress) {
  let chef = await returnChef(chefAddress);
  let poolLength = await chef.poolLength();
  return poolLength;
}

async function addPool(operator, chefAddress, allocPoint, lpToken, rewarder, curve, name, isLP) {
  let chef = await returnChef(chefAddress);
  let tx = await chef.connect(operator).addPool(allocPoint, lpToken, rewarder, curve, name, isLP);
  let receipt = await tx.wait();
  return receipt;
}

async function modifyPool(chefAddress, pid, allocPoint, rewarder, curve, name, isLP, overwriteRewarder) {
  let chef = await returnChef(chefAddress);
  let tx = await chef.modifyPool(pid, allocPoint, rewarder, curve, name, isLP, overwriteRewarder);
  let receipt = await tx.wait();
  return receipt;
}

async function pendingOath(chefAddress, positionId) {
  let chef = await returnChef(chefAddress);
  let pending = await chef.pendingOath(positionId);
  return pending;
}

async function massUpdatePools(chefAddress, pids) {
  let chef = await returnChef(chefAddress);
  let tx = await chef.massUpdatePools(pids);
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
  let tx = await chef.createRelicAndDeposit(to, pid, amount);
  let receipt = await tx.wait();
  return receipt;
}

async function deposit(chefAddress, amount, positionId) {
  let chef = await returnChef(chefAddress);
  let tx = await chef.deposit(amount, positionId);
  let receipt = await tx.wait();
  return receipt;
}

async function withdraw(chefAddress, amount, positionId) {
  let chef = await returnChef(chefAddress);
  let tx = await chef.withdraw(amount, positionId);
  let receipt = await tx.wait();
  return receipt;
}

async function harvest(chefAddress, positionId) {
  let chef = await returnChef(chefAddress);
  let tx = await chef.harvest(positionId);
  let receipt = await tx.wait();
  return receipt;
}

async function withdrawAndHarvest(chefAddress, amount, positionId) {
  let chef = await returnChef(chefAddress);
  let tx = await chef.harvest(amount, positionId);
  let receipt = await tx.wait();
  return receipt;
}

async function emergencyWithdraw(chefAddress, positionId) {
  let chef = await returnChef(chefAddress);
  let tx = await chef.emergencyWithdraw(positionId);
  let receipt = await tx.wait();
  return receipt;
}

async function curved(chefAddress, positionId) {
  let chef = await returnChef(chefAddress);
  let curvedValue = await chef.curved(positionId);
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
  deployNFTDescriptor,
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
  addPool,
  modifyPool,
  pendingOath,
  massUpdatePools,
  updatePool,
  createNewPositionAndDeposit,
  deposit,
  withdraw,
  harvest,
  withdrawAndHarvest,
  emergencyWithdraw,
  curved,
};
