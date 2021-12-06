const tokens = require("../tokens.json");
const addresses = require("../Addresses.json");

let BigGas = { gasPrice: 500000000000, gasLimit: 10000000 }

async function parseToken(amount, tokenAddress) {
  let decimals;
  if (typeof tokenAddress == "undefined") {
    decimals = 18;
  } else {
    let TestERC20 = await ethers.getContractFactory("TestERC20");
    let token = TestERC20.attach(tokenAddress);
    decimals = await token.decimals();
  }
  let amt = amount.toString();
  let ether = ethers.utils.parseUnits(amt, decimals);
  return ether;
}

async function createContract(contractType, address) {
  if (contractType == "ERC20") {
    contractType = "TestERC20";
  }
  let template = await ethers.getContractFactory(contractType);
  let contract = template.attach(address);
  return contract;
}

async function addFarm(chefAddress, targetToken, allocation) {
  let MasterChef = await ethers.getContractFactory("MasterChef");
  let chef = await MasterChef.attach(chefAddress);
  const tx = await chef.add(allocation, targetToken, false);
  let receipt = await tx.wait();
  return receipt;
}

async function depositToFarm(chefAddress, pid, amount) {
  let MasterChef = await ethers.getContractFactory("MasterChef");
  let chef = await MasterChef.attach(chefAddress);
  let poolInfo = await getPoolInfo(chefAddress, pid);
  await approveMax(chefAddress, poolInfo.lpToken);
  let tx = await chef.deposit(pid, amount);
  let receipt = await tx.wait();
  return receipt;
}

async function getPairAddress(factoryAddress, tokenOne, tokenTwo) {
  let Factory = await ethers.getContractFactory("UniswapV2Factory");
  let factory = await Factory.attach(factoryAddress);
  let lpAddr = await factory.getPair(tokenOne, tokenTwo);
  if (lpAddr === ethers.constants.AddressZero) {
    let tx = await factory.createPair(tokenOne, tokenTwo);
    await tx.wait();
    lpAddr = await factory.getPair(tokenOne, tokenTwo);
  }
  return lpAddr;
}

async function addLiquidity(
  routerAddress,
  tokenOne,
  tokenTwo,
  amountOne,
  amountTwo,
  toAddress
) {
  let Router = await ethers.getContractFactory("UniswapV2Router02");
  let router = await Router.attach(routerAddress);
  await approveMax(routerAddress, [tokenOne, tokenTwo]);
  let self = await ethers.provider.getSigner(0);
  let selfAddress = await self.getAddress();
  let timestamp = await getTimestamp();
  let tx = await router.addLiquidity(
    tokenOne,
    tokenTwo,
    amountOne,
    amountTwo,
    1,
    1,
    selfAddress,
    timestamp+50
  );
  let receipt = await tx.wait();
  return receipt;
}

async function getTimestamp() {
  let bNum = await ethers.provider.getBlockNumber();
  let block = await ethers.provider.getBlock(bNum);
  return block.timestamp;
}

async function deployMasterChef(adminAddress, emissionsPerSecond, delay) {
  let MasterChef = await ethers.getContractFactory("MasterChef");
  let SushiToken = await ethers.getContractFactory("SushiToken");
  let sushi = await SushiToken.deploy();;
  let timestamp = await getTimestamp();
  let chef = await MasterChef.deploy(
    sushi.address,
    adminAddress,
    emissionsPerSecond,
    timestamp+delay
  );
  let tx = await sushi.transferOwnership(chef.address);
  await tx.wait();
  console.log("sushi address "+sushi.address);
  let sushiowner = await sushi.owner();
  console.log("sushi owner " +sushiowner);
  console.log("chef address " +chef.address);
  return chef;
}

async function updatePools(chefAddress) {
  let MasterChef = await ethers.getContractFactory("MasterChef");
  let chef = MasterChef.attach(chefAddress);
  let tx = await chef.massUpdatePools();
  let receipt = await tx.wait();
  return receipt;
}

async function getUserInfo(chefAddress, pid, userAddress) {
  let MasterChef = await ethers.getContractFactory("MasterChef");
  let chef = await MasterChef.attach(chefAddress);
  let userInfo = await chef.userInfo(pid, userAddress);
  return {
    "amount": userInfo[0],
    "rewardDebt": userInfo[1]
  }
}

async function getPoolInfo(chefAddress, pid) {
  let MasterChef = await ethers.getContractFactory("MasterChef");
  let chef = await MasterChef.attach(chefAddress);
  let poolInfo = await chef.poolInfo(pid);
  return {
    "lpToken": poolInfo[0],
    "allocPoint": poolInfo[1],
    "lastRewardTime": poolInfo[2],
    "accsushiPerShare": poolInfo[3]
  };
}

async function getPoolLength(chefAddress) {
  let MasterChef = await ethers.getContractFactory("MasterChef");
  let chef = await MasterChef.attach(chefAddress);
  let length = await chef.poolLength();
  return length;
}

async function deployTestToken(name, symbol) {
  let TestERC20 = await ethers.getContractFactory("TestERC20");
  let token = await TestERC20.deploy(name, symbol);
  return token;
}

async function getTokenMetadata(tokenAddress) {
  let TestERC20 = await ethers.getContractFactory("TestERC20");
  let token = TestERC20.attach(tokenAddress);
  let name = await token.name();
  let symbol = await token.symbol();
  let decimals = await token.decimals();
  let totalSupply = await token.totalSupply();
  totalSupply = await format(tokenAddress, totalSupply);
  let owner = await token.owner();
  return {
    "name": name,
    "symbol": symbol,
    "decimals": decimals,
    "totalSupply": totalSupply,
    "owner": owner
  }
}

async function mintTestToken(tokenAddress, userAddress, amount) {
  let TestERC20 = await ethers.getContractFactory("TestERC20");
  let token = await TestERC20.attach(tokenAddress);
  let tx = await token.mint(userAddress, amount);
  await tx.wait();
  let balance = await token.balanceOf(userAddress);
  balance = await formatToken(balance, tokenAddress);
  return balance;
}

async function getUserBalance(userAddress, tokenAddress) {
  let balance;
  if (tokenAddress == undefined) {
    balance = await ethers.provider.getBalance(userAddress);
    return balance;
  } else {
    let TestERC20 = await ethers.getContractFactory("TestERC20");
    let token = await TestERC20.attach(tokenAddress);
    balance = await token.balanceOf(userAddress);
    return balance;
  }
}

async function createRoute(tokenInput, tokenOutput) {
  if (tokenInput === tokens.wftm || tokenOutput === tokens.wftm) {
    return [tokenInput, tokenOutput]
  } else {
    return [tokenInput, tokens.wftm, tokenOutput]
  }
}

async function approveMax(spenderAddress, tokenAddresses) {
  if (tokenAddresses.length == 42) {
    tokenAddresses = [tokenAddresses];
  }
  let TestERC20 = await ethers.getContractFactory("TestERC20");
  let token;
  for(let i = 0; i < tokenAddresses.length; i++) {
    token = TestERC20.attach(tokenAddresses[i]);
    let tx = await token.approve(spenderAddress, ethers.constants.MaxUint256);
    let receipt = await tx.wait();
  } return "success";
}

async function swap(
  routerAddress,
  tokenInput,
  tokenOutput,
  toAddress,
  amountIn,
  slippage
) {
  let Router = await ethers.getContractFactory("UniswapV2Router02");
  let exchange = await Router.attach(exchangeAddress)
  let timestamp = await getTimestamp();
  let route = await createRoute(tokenInput, tokenOutput);
  await approveMax(routerAddress, [tokenInput, tokenOutput]);
  let tx = await exchange.swapExactTokensForTokensSupportingFeeOnTransferTokens(
    amountIn,
    0,
    route,
    toAddress,
    timestamp+60
  );
  let receipt = await tx.wait();
  return receipt;
}

function sleep(milliseconds) {
  const date = Date.now();
  let currentDate = null;
  do {
    currentDate = Date.now();
  } while (currentDate - date < milliseconds);
}

async function formatToken(amount, tokenAddress) {
  let decimals;
  let result;
  if (tokenAddress == BigGas) {
    tokenAddress = undefined;
  }
  if (tokenAddress == undefined) {
    decimals = 18;
  } else {
    let TestERC20 = await ethers.getContractFactory("TestERC20");
    let token = TestERC20.attach(tokenAddress)
    decimals = await token.decimals();
  }
  if (decimals === 18) {
    result = ethers.utils.formatEther(amount);
  } else {
    result = ethers.utils.formatUnits(amount, decimals);
  }
  if (typeof result === "string") {
    return parseFloat(result);
  }
  return result;
}

async function advanceTime(amount) {
  await ethers.provider.send("evm_increaseTime", amount);
}

async function advanceBlocks(amount) {
  for(let i = 0; i<amount; i++) {
    await ethers.provider.send("evm_mine");
  }
}

module.exports = {
  //constants
  BigGas,
  //token
  deployTestToken,
  mintTestToken,
  approveMax,
  getTokenMetadata,
  getUserBalance,
  //chef
  deployMasterChef,
  addFarm,
  depositToFarm,
  getPoolInfo,
  getPoolLength,
  getUserInfo,
  updatePools,
  //Uniswap
  createRoute,
  swap,
  addLiquidity,
  getPairAddress,
  //utilities
  createContract,
  parseToken,
  formatToken,
  sleep,
  getTimestamp
}
