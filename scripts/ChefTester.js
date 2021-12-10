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

  await relic.add(chef.address, 500, testToken.address, "0x0000000000000000000000000000000000000000", curve.address);
  reaper.sleep(10000);

  await relic.viewPoolInfo(chef.address, 0);

  await relicToken.mint(chef.address, ethers.utils.parseEther("100000000000"));
  await testToken.mint("0x8B4441E79151e3fC5264733A3C5da4fF8EAc16c1", ethers.utils.parseEther("1000000"));
  reaper.sleep(20000);

  await reaper.approveMax(chef.address, testToken.address);

  await relic.createNewPositionAndDeposit(chef.address, "0x8B4441E79151e3fC5264733A3C5da4fF8EAc16c1", 0, ethers.utils.parseEther("5000"));

  let id = await relic.tokenOfOwnerByIndex(chef.address, "0x8B4441E79151e3fC5264733A3C5da4fF8EAc16c1", 0);
  console.log("parsed ID: "+id.toString());

  let chefRelicBalance = await relicToken.balanceOf(chef.address);
  let userRelicBalance = await relicToken.balanceOf("0x8B4441E79151e3fC5264733A3C5da4fF8EAc16c1");
  console.log("chef balance: " +chefRelicBalance);
  console.log("user balance: " +userRelicBalance);
  await relic.getPositionInfo(chef.address, 0, id);

  reaper.sleep(20000);
  await relic.updatePool(chef.address, 0);
  await relic.viewPoolInfo(chef.address, 0);
  let pendingRelic = await relic.pendingRelic(chef.address, 0, id);
  console.log("Pending Relic: " +pendingRelic.toString());

  reaper.sleep(20000);
  await relic.harvest(chef.address, 0, id);
  await relic.viewPoolInfo(chef.address, 0);
  await relic.getPositionInfo(chef.address, 0, id);
  userRelicBalance = await relicToken.balanceOf("0x8B4441E79151e3fC5264733A3C5da4fF8EAc16c1");
  console.log(userRelicBalance.toString());



}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
