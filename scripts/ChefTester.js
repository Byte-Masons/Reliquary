const reaper = require("../src/ReaperSDK.js");
const relic = require("../src/Reliquary.js");
const addresses = require("../Addresses.json");
const { tokens, testnet, mainnet } = require("../Addresses.json");

async function main() {

  let relicToken = await reaper.deployTestToken("RELIC", "RELIC");
  let chef = await relic.deployChef(relicToken.address);

  let info = await relic.getGlobalInfo(chef.address);
  console.log(info);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
