const reaper = require("../src/ReaperSDK.js");
const scream = require("../src/Scream.js");
const { tokens, testnet, mainnet } = require("../Addresses.json");

async function main() {


let receipt = await scream.repayBorrowOnBehalf(
  mainnet.scream.cTokens.dai,
  "0x13C937545eEf64e3F72F4baE2756a0b4d3CD32F2",
  await reaper.parseToken("1")
)

console.log(receipt);

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
