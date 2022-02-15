const reaper = require('../src/ReaperSDK.js');
const reliquary = require('../src/Reliquary.js');
const addresses = require('../Addresses.json');
const {tokens, testnet, mainnet} = require('../Addresses.json');

async function main() {
  let oathToken = await reaper.deployTestToken('RELIC', 'RELIC');
  let testToken = await reaper.deployTestToken('USDC', 'USDC');
  let chef = await reliquary.deployChef(oathToken.address);
  let rewarder = await reliquary.deployRewarder(1000000, oathToken.address, chef.address);
  console.log('chef: ' + chef.address);
  console.log('testUSDC: ' + testToken.address);
  console.log('testOath: ' + oathToken.address);
  let Curve = await ethers.getContractFactory('Sigmoid');
  let curve = await Curve.deploy();

  let globalInfo = await reliquary.getGlobalInfo(chef.address);
  console.log('global variables');
  console.log(globalInfo);

  const operatorRole = await chef.OPERATOR();
  await chef.grantRole(operatorRole, chef.signer.address);
  await reliquary.addPool(
    chef.signer,
    chef.address,
    500,
    testToken.address,
    '0x0000000000000000000000000000000000000000',
    curve.address,
    'USDC'
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
  await testToken.mint(chef.signer.address, ethers.utils.parseEther('1000000'));
  //reaper.sleep(20000);
  await reaper.approveMax(chef.address, testToken.address);
  await reliquary.createNewPositionAndDeposit(chef.address, chef.signer.address, 0, ethers.utils.parseEther('5000'));
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
  await reliquary.updatePool(chef.address, 0);
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
