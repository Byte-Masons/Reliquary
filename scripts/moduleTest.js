const reaper = require("../src/ReaperSDK.js");
const addresses = require("../Addresses.json");
const { tokens, testnet, mainnet } = require("../Addresses.json");

async function main() {

  let self = "0x8B4441E79151e3fC5264733A3C5da4fF8EAc16c1";

  const dai = await reaper.deployTestToken("Test DAI", "tDAI", reaper.BigGas);
  console.log(dai.address);
  reaper.sleep(5000);

  const reap = await reaper.deployTestToken("Reaper SDK", "REAP", reaper.BigGas);
  console.log(reap.address);
  reaper.sleep(5000);

  await reaper.mintTestToken(dai.address, self, await reaper.parseToken("10000000000"));
  await reaper.mintTestToken(reap.address, self, await reaper.parseToken("500000000"));
  reaper.sleep(3000);

  let daiBalance = await reaper.getUserBalance(self, dai.address);
  let byteBalance = await reaper.getUserBalance(self, reap.address);
  console.log("Test Dai Balance: " +daiBalance.toString());
  console.log("reap Balance: " +byteBalance.toString());

  await reaper.addLiquidity(
    testnet.router,
    dai.address,
    reap.address,
    daiBalance,
    byteBalance
  );

  reaper.sleep(30000);

  daiBalance = await reaper.getUserBalance(self, dai.address);
  byteBalance = await reaper.getUserBalance(self, reap.address);
  console.log("Test Dai Balance: " +daiBalance.toString());
  console.log("reap Balance: " +byteBalance.toString());
  reaper.sleep(30000);

  let lpAddr = await reaper.getPairAddress(
    testnet.factory,
    dai.address,
    reap.address
  );

  let balance = await reaper.getUserBalance(self, lpAddr);
  console.log("balance " +balance.toString());

  let chef = await reaper.deployMasterChef(
    self,
    await reaper.parseToken("0.1"),
    15
  );
  reaper.sleep(30000);
  let owner = await chef.owner();
  console.log("owner "+owner);
  console.log("chef " +chef.address);
  await reaper.addFarm(chef.address, lpAddr, 4000);

  reaper.sleep(30000);
  console.log("fuck");
  await reaper.depositToFarm(
    chef.address,
    0,
    balance
  );
  reaper.sleep(30000);
  await reaper.updatePools(chef.address);
  reaper.sleep(30000);
  console.log("balls");
  let position = await reaper.getUserInfo(chef.address, 0, self);
  console.log(position);
  console.log("My DAI-REAP Farm Position: " +position.amount);
  console.log("My Pending Rewards: " +position.rewardDebt);

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
