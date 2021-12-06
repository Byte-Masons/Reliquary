const tokens = require("../tokens.json");
const reaper = require("./ReaperSDK.js");

async function getCompRate(compAddress) {
  let Comp = await ethers.getContractFactory("ComptrollerV3Storage");
  let comp = await Comp.attach(compAddress);
  let rate = await comp.compRate();
  return rate.toString();
}

async function viewMarket(compAddress, index) {
  let Comp = await ethers.getContractFactory("ComptrollerV3Storage");
  let comp = await Comp.attach(compAddress);
  let marketAddress = await comp.allMarkets(index);
  let marketRate = await comp.compSpeeds(marketAddress);
  return {
    "marketAddress": marketAddress,
    "marketRate": marketRate.toString()
  }
}

async function viewCompSpeed(compAddress, marketAddress) {
  let Comp = await ethers.getContractFactory("ComptrollerV3Storage");
  let comp = await Comp.attach(compAddress);
  let marketRate = await comp.compSpeeds(marketAddress);
  return marketRate;
}

async function viewCompState(compAddress, type, index) {
  let Comp = await ethers.getContractFactory("ComptrollerV3Storage");
  let comp = await Comp.attach(compAddress);
  let marketAddress = await comp.allMarkets(index);
  console.log(marketAddress);
  if(type == "borrow") {
    let state = comp.compBorrowState(marketAddress);
    return state;
  } else if (type == "supply") {
    let state = comp.compSupplyState(marketAddress);
    return state;
  }
}

async function repayBorrowOnBehalf(cTokenAddress, borrower, amount) {
  let Comp = await ethers.getContractFactory("CErc20");
  let comp = await Comp.attach(cTokenAddress);
  await reaper.approveMax("0x8D9AED9882b4953a0c9fa920168fa1FDfA0eBE75", tokens.dai)
  let tx = await comp.repayBorrowBehalf(borrower, amount);
  let receipt = await tx.wait();
  return receipt;
}

async function viewSupplyBalance(cTokenAddress, owner) {
  let Comp = await ethers.getContractFactory("CErc20");
  let comp = await Comp.attach(cTokenAddress);
  let balance = await comp.balanceOfUnderlying(owner);
  return balance;
}

module.exports = {
  getCompRate,
  viewMarket,
  viewCompState,
  repayBorrowOnBehalf,
  viewSupplyBalance
}
