const reaper = require('../src/ReaperSDK.js');
const reliquary = require('../src/Reliquary.js');
const addresses = require('../Addresses.json');
const {tokens, testnet, mainnet} = require('../Addresses.json');

async function main() {
  let oathToken = await reaper.deployTestToken('OATH', 'OATH');
  let testToken = await reaper.deployTestToken('USDC', 'USDC');
  let UniV2Factory = await ethers.getContractFactory('UniswapV2Factory');
  let uniV2Factory = await UniV2Factory.deploy('0x0000000000000000000000000000000000000000');
  await uniV2Factory.createPair(oathToken.address, testToken.address);
  //reaper.sleep(10000);
  let pairAddress = await uniV2Factory.getPair(oathToken.address, testToken.address);
  let Pair = await ethers.getContractFactory('UniswapV2Pair');
  let pair = await Pair.attach(pairAddress);
  let nftDescriptor = await reliquary.deployNFTDescriptor();
  let Constant = await ethers.getContractFactory('Constant');
  let emissionSetter = await Constant.deploy();
  let chef = await reliquary.deployChef(oathToken.address, nftDescriptor.address, emissionSetter.address);
  let rewarder = await reliquary.deployRewarder(1000000, oathToken.address, chef.address);
  console.log('chef: ' + chef.address);
  console.log('testUSDC: ' + testToken.address);
  console.log('testOath: ' + oathToken.address);
  console.log('testLP: ' + pair.address);
  let curve = [
    { requiredMaturity: 0, allocPoint: 25, balance: 0 },
    { requiredMaturity: 24 * 60 * 60 * 60, allocPoint: 50, balance: 0 },
    { requiredMaturity: 24 * 60 * 60 * 120, allocPoint: 75, balance: 0 },
    { requiredMaturity: 24 * 60 * 60 * 150, allocPoint: 90, balance: 0 },
    { requiredMaturity: 24 * 60 * 60 * 180, allocPoint: 100, balance: 0 },
    { requiredMaturity: 24 * 60 * 60 * 240, allocPoint: 110, balance: 0 },
    { requiredMaturity: 24 * 60 * 60 * 600, allocPoint: 120, balance: 0 }
  ];

  let globalInfo = await reliquary.getGlobalInfo(chef.address);
  console.log('global variables');
  console.log(globalInfo);

  const operatorRole = await chef.OPERATOR();
  await chef.grantRole(operatorRole, chef.signer.address);
  reaper.sleep(10000);
  await reliquary.addPool(
    chef.signer,
    chef.address,
    500,
    pair.address,
    '0x0000000000000000000000000000000000000000',
    curve,
    'USDC-OATH',
    true
  );
  //reaper.sleep(10000);

  let globalInfo2 = await reliquary.getGlobalInfo(chef.address);
  console.log('global variables');
  console.log(globalInfo2);

  let poolInfo = await reliquary.viewPoolInfo(chef.address, 0);
  console.log(poolInfo);

  let poolCount = await reliquary.getPoolCount(chef.address);
  console.log('pool count: ' + poolCount.toString());

  let lpTokenAddress = await reliquary.viewLpToken(chef.address, 0);
  let rewarderAddress = await reliquary.viewRewarder(chef.address, 0);
  console.log('lpToken address: ' + lpTokenAddress);
  console.log('rewarderAddress: ' + rewarderAddress);

  await oathToken.mint(chef.address, ethers.utils.parseEther('100000000000'));
  await oathToken.mint(pair.address, ethers.utils.parseEther('100.1234'));
  await testToken.mint(pair.address, ethers.utils.parseEther('1000000'));
  //reaper.sleep(10000);
  await pair.mint(chef.signer.address);
  //reaper.sleep(10000);
  let pairBalance = await pair.balanceOf(chef.signer.address);
  //reaper.sleep(10000);
  await reaper.approveMax(chef.address, pair.address);
  await reliquary.createNewPositionAndDeposit(chef.address, chef.signer.address, 0, pairBalance);
  let id = await reliquary.tokenOfOwnerByIndex(chef.address, chef.signer.address, 0);
  console.log('NFT IDs');
  console.log(id);
  console.log('parsed ID: ' + id.toString());
  let chefOathBalance = await oathToken.balanceOf(chef.address);
  let userOathBalance = await oathToken.balanceOf(chef.signer.address);
  console.log('chef balance: ' + chefOathBalance);
  console.log('user balance: ' + userOathBalance);
  let positionInfo = await reliquary.getPositionInfo(chef.address, id);
  console.log('Position Info:');
  console.log(positionInfo);

  //reaper.sleep(30000);
  await network.provider.send('evm_increaseTime', [31557600 * 1.5]);
  await network.provider.send('evm_mine');
  await reliquary.updatePool(chef.address, 0, reaper.BigGas);
  await chef.updatePosition(id);
  //await reliquary.harvest(chef.address, id);
  //reaper.sleep(10000);
  console.log(await chef.tokenURI(id));
  const json = Buffer.from((await chef.tokenURI(id)).replace('data:application/json;base64,', ''), 'base64').toString();
  console.log(json);
  const imageB64 = String(json.split(',').pop());
  const html = Buffer.from(imageB64.substr(0, imageB64.length - 2), 'base64').toString();
  console.log(html);
  let poolInfo2 = await reliquary.viewPoolInfo(chef.address, 0);
  console.log(poolInfo2);
  let pendingOath = await reliquary.pendingOath(chef.address, 0, id);
  console.log('Pending Oath: ' + pendingOath.toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
