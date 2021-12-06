const reaper = require("../src/ReaperSDK.js");
const addresses = require("../Addresses.json");
const { tokens, testnet, mainnet } = require("../Addresses.json");

async function main() {

  const dai = "0xdc9014739716a282631169c670C1BA7a68Eee68A";
  const reap = "0x3EC30f9b4e857f59F6Ab84Ca7f0A23d0C4eB9aa2";
  const sushi = "0xC79D4575b2E00B164Cf28cCe14A75255A74DA30f";
  const chef = "0x7E3373960A071bC70434D2c0924DA6A544b4bc16";
  const self = "0x8B4441E79151e3fC5264733A3C5da4fF8EAc16c1";

/*  await reaper.updatePools(chef);
  reaper.sleep(30000);
  let userInfo = await reaper.getUserInfo(chef, 0, self);
  console.log(userInfo);

  let poolInfo = await reaper.getPoolInfo(chef, 0);
  console.log(poolInfo);
*/
  let cheff = await reaper.createContract("MasterChef", chef);

  await reaper.depositToFarm(chef, 0, 0);

  await reaper.updatePools(chef);
  reaper.sleep(30000);
  userInfo = await reaper.getUserInfo(chef, 0, self);
  console.log(userInfo);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
