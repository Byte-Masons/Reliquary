function debug(arguments) {
  let argumentTypes;
  for (let i = 0; i < arguments.length; i++) {
    argumentTypes.push(typeof arguments[i]);
  }
  return argumentTypes;
}

async function deployChef(oathAddress, emissionSetterAddress) {
  let Reliquary = await ethers.getContractFactory('Reliquary');
  let chef = await Reliquary.deploy(oathAddress, emissionSetterAddress);
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
    totalAllocPoint: (await chef.totalAllocPoint()).toString(),
    chefToken: await chef.OATH(),
    emissionSetter: await chef.emissionSetter()
  };
  return globalInfo;
}

async function deployNFTDescriptor(chefAddress, numCharacters) {
  let NFTDescriptor = await ethers.getContractFactory('NFTDescriptor');
  let nftDescriptor = await NFTDescriptor.deploy(chefAddress, numCharacters);
  return nftDescriptor;
}

async function deployRewarder(multiplier, depositBonus, minimum, cadence, token, chefAddress) {
  let Rewarder = await ethers.getContractFactory('Rewarder');
  let rewarder = await Rewarder.deploy(multiplier, depositBonus, minimum, cadence, token, chefAddress);
  return rewarder;
}

async function deployCurve() {
  let Curve = await ethers.getContractFactory('EighthRoot');
  let curve = await Curve.deploy();
  return curve;
}

async function viewPoolInfo(chefAddress, pid) {
  let chef = await returnChef(chefAddress);
  let poolInfo = await chef.getPoolInfo(pid);
  let obj = {
    accOathPerShare: poolInfo[0].toString(),
    lastRewardTime: poolInfo[1].toString(),
    allocPoint: poolInfo[2].toString(),
    name: poolInfo[3],
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
  let userInfo = await chef.getPositionForId(positionId);
  return {
    amount: userInfo[0].toString(),
    rewardDebt: userInfo[1].toString(),
    rewardCredit: userInfo[2].toString(),
    entry: userInfo[3].toString(),
    poolId: userInfo[4].toString(),
    level: userInfo[5].toString()
  };
}

async function getPoolCount(chefAddress) {
  let chef = await returnChef(chefAddress);
  let poolLength = await chef.poolLength();
  return poolLength;
}

async function addPool(operator, chefAddress, allocPoint, lpToken, rewarder, requiredMaturity, allocPoints, name, nftDescriptor) {
  let chef = await returnChef(chefAddress);
  let tx = await chef.connect(operator).addPool(allocPoint, lpToken, rewarder, requiredMaturity, allocPoints, name, nftDescriptor);
  let receipt = await tx.wait();
  return receipt;
}

async function modifyPool(chefAddress, pid, allocPoint, rewarder, name, nftDescriptor, overwriteRewarder) {
  let chef = await returnChef(chefAddress);
  let tx = await chef.modifyPool(pid, allocPoint, rewarder, name, nftDescriptor, overwriteRewarder);
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

async function tokenURI(chefAddress, positionId) {
  let chef = await returnChef(chefAddress);
  let uri = chef.tokenURI(positionId);
  return uri;
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
  tokenURI
};
