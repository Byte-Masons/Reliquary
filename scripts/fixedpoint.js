const reaper = require("../src/ReaperSDK.js");

async function main() {

  let Babylon = await ethers.getContractFactory("babylon");
  let bab = await Babylon.deploy();

  let Root = await ethers.getContractFactory("FixedPointPoop");
  let Full = await ethers.getContractFactory("FullMath");
  let full = await Full.deploy();
  reaper.sleep(10000);
  let root = await Root.deploy(full.address);

  let fraction = await root.fraction(ethers.utils.parseEther("732408000000000000000000"), ethers.utils.parseEther("2000000"));
  console.log(fraction.toString());
  console.log(fraction);
  let decoded = await root.decode112with18(fraction);
  console.log(decoded);
  console.log(decoded.toString());
  let divided = await bab.div(decoded, ethers.utils.parseEther("1"));
  console.log(divided);
  console.log(divided.toString());


}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
