const reaper = require("../src/ReaperSDK.js");
const relic = require("../src/Reliquary.js");
const addresses = require("../Addresses.json");
const { tokens, testnet, mainnet } = require("../Addresses.json");

async function main() {

  let relicToken = await reaper.deployTestToken("RELIC", "RELIC");
  let testToken = await reaper.deployTestToken("USDC", "USDC");
  let chef = await relic.deployChef(relicToken.address);
  let rewarder = await relic.deployRewarder(1000000, relicToken.address, chef.address);
  console.log("chef: " +chef.address);
  console.log("testUSDC: " +testToken.address);
  console.log("testRelic: " +relicToken.address);
  let curve = await relic.deployCurve();

  let globalInfo = await relic.getGlobalInfo(chef.address);
  console.log("global variables");
  console.log(globalInfo);

  await relic.add(chef.address, 500, relicToken.address, "0x0000000000000000000000000000000000000000", curve.address);
  reaper.sleep(10000);

  let poolInfo = await relic.viewPoolInfo(chef.address, 0);
  console.log(poolInfo);

  let poolCount = await relic.getPoolCount(chef.address);
  console.log("pool count: " +poolCount.toString());

  let lpTokenAddress = await relic.viewLpToken(chef.address, 0);
  let rewarderAddress = await relic.viewRewarder(chef.address, 0);
  console.log("lpToken address: " +lpTokenAddress);
  console.log("rewarderAddress: " +rewarderAddress);

  await relicToken.mint(chef.address, ethers.utils.parseEther("100000000000"));
  await relicToken.mint("0x8B4441E79151e3fC5264733A3C5da4fF8EAc16c1", ethers.utils.parseEther("1000000"));
  reaper.sleep(20000);
  await reaper.approveMax(chef.address, relicToken.address);
  await relic.createNewPositionAndDeposit(chef.address, "0x8B4441E79151e3fC5264733A3C5da4fF8EAc16c1", 0, ethers.utils.parseEther("5000"));
  let id = await relic.tokenOfOwnerByIndex(chef.address, "0x8B4441E79151e3fC5264733A3C5da4fF8EAc16c1", 0);
  console.log("NFT IDs");
  console.log(id);
  console.log("parsed ID: "+id.toString());
  let chefRelicBalance = await relicToken.balanceOf(chef.address);
  let userRelicBalance = await relicToken.balanceOf("0x8B4441E79151e3fC5264733A3C5da4fF8EAc16c1");
  console.log("chef balance: " +chefRelicBalance);
  console.log("user balance: " +userRelicBalance);
  let positionInfo = await relic.getPositionInfo(chef.address, 0, id);
  console.log("Position Info:")
  console.log(positionInfo);

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
