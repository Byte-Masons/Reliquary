const { expect } = require("chai");
const { waffle } = require("hardhat");
const pools = require("../pools.json");
const tokens = require("../tokens.json");
const UNISWAP = require('@uniswap/sdk');
const hre = require("hardhat");

describe("Vaults", function () {

  beforeEach(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [{
        forking: {
          jsonRpcUrl: "https://rpc.ftm.tools/",
          blockNumber: 11238828
        }
      }]
    });
  });

  describe("Testing the v2 strategy", function () {
    it("does the needful", async function () {
      let Vault = await ethers.getContractFactory("ReaperVault");
      let Strategy = await ethers.getContractFactory("ReaperAutoCompoundSteakv2");
      let TestHelper = await ethers.getContractFactory("TestHelper");
      let Treasury = await ethers.getContractFactory("ReaperTreasury");

      //dependencies
      let ERC20 = await ethers.getContractFactory("contracts/Treasury.sol:ERC20");
      let WFTM = await ethers.getContractFactory("WrappedFtm");
      let UniToken = await ethers.getContractFactory("UniswapV2ERC20")
      let MasterChef = await ethers.getContractFactory("MasterChef");
      let MasterChefIce = await ethers.getContractFactory("Sorbettiere");
      let MasterChefSteakV2 = await ethers.getContractFactory("SteakHouseV2");
      let UniRouter = await ethers.getContractFactory("UniswapV2Router02");
      let UniFactory = await ethers.getContractFactory("UniswapV2Factory");
      let UniPair = await ethers.getContractFactory("UniswapV2Pair");

      let vault;
      let strategy;
      let treasury;
      let targetToken;

      let wftm = await WFTM.deploy();
      let uniFactory = await UniFactory.deploy()
      let helper = await TestHelper.deploy();
      let wftm = WFTM.attach(tokens.wftm);

      let self;
      let user1;
      let user2;
      let user3;
      let user4;

      [self, user1, user2, user3, user4, ...users] = await ethers.getSigners();
      const selfAddress = await self.getAddress();
      const user1Address = await user1.getAddress();
      const user2Address = await user2.getAddress();
      const user3Address = await user3.getAddress();
      const user4Address = await user4.getAddress();

      let BFN = ethers.utils.parseEther("1000000000000");
      BFN = BFN._hex.replace(/0x0+/, "0x");

      async function printFTM() {
        await network.provider.send("hardhat_setBalance", [ selfAddress, BFN ] );
        await network.provider.send("hardhat_setBalance", [ user1Address, BFN ] );
        await network.provider.send("hardhat_setBalance", [ user2Address, BFN ] );
        await network.provider.send("hardhat_setBalance", [ user3Address, BFN ] );
        await network.provider.send("hardhat_setBalance", [ user4Address, BFN ] );
      }

      async function wrapFTM() {
        await wftm.deposit({ value: ethers.utils.parseEther("1000000000") });
        await wftm.connect(user1).deposit({ value: ethers.utils.parseEther("10000000") });
        await wftm.connect(user2).deposit({ value: ethers.utils.parseEther("10000000") });
        await wftm.connect(user3).deposit({ value: ethers.utils.parseEther("10000000") });
        await wftm.connect(user4).deposit({ value: ethers.utils.parseEther("10000000") });
      }

      async function moneyBoost() {
        await printFTM();
        await wrapFTM();
      }

      async function reset() {
        await network.provider.request({
          method: "hardhat_reset",
          params: [{
            forking: {
              jsonRpcUrl: "https://rpcapi.fantom.network/",
              blockNumber: 11238828
            }
          }]
        });
      }

      async function swap(signer, exchange, amountIn, targetToken) {
        const signerAddress = await signer.getAddress();
        let target = await ERC20.attach(targetToken);
        await wftm.connect(signer).approve(exchange.address, ethers.utils.parseEther("1000000000"));
        await wftm.connect(signer).approve(helper.address, ethers.utils.parseEther("1000000000"));
        let allowance = await wftm.connect(signer).allowance(signerAddress, helper.address);
        console.log(allowance.toString());
        let tx = await helper.connect(signer).swap(
          exchange.address,
          amountIn,
          targetToken,
          signerAddress
        );
        let receipt = await tx.wait();
        console.log(receipt);
      }

      async function moneyBlast(exchange, factory, tokenOne, tokenTwo, amount) {
        await addLiquidity(user1, exchange, factory, tokenOne, tokenTwo, amount);
        await addLiquidity(user2, exchange, factory, tokenOne, tokenTwo, amount);
        await addLiquidity(user3, exchange, factory, tokenOne, tokenTwo, amount);
        await addLiquidity(user4, exchange, factory, tokenOne, tokenTwo, amount);
      }

      async function addLiquidity(
        signer,
        exchange,
        factory,
        tokenOne,
        tokenTwo,
        amount,
      ) {
        const signerAddress = await signer.getAddress();
        let tok1c = await ERC20.attach(tokenOne);
        let tok2c = await ERC20.attach(tokenTwo);
        await tok1c.connect(signer).approve(factory.address, ethers.utils.parseEther("10000000000"));
        await tok2c.connect(signer).approve(factory.address, ethers.utils.parseEther("10000000000"));
        const half = amount.div(2);
        console.log("swap");
        await swap(signer, exchange, half, tokenOne);
        await swap(signer, exchange, half, tokenTwo);
        console.log("balance determination");
        let lp0bal = tok1c.balanceOf(signerAddress);
        let lp1bal = tok2c.balanceOf(signerAddress);
        console.log("add liquidity");
        await factory.addLiquidity(
          tokenOne,
          tokenTwo,
          lp0bal,
          lp1bal,
          1,
          1,
          signerAddress,
          0
        );
        console.log("complete");
      }

      async function deploy(targetFarm) {
        targetToken = UniToken.attach(targetFarm.lpToken.address);

        vault = await Vault.deploy(
          targetFarm.lpToken.address,
          targetFarm.name,
          targetFarm.symbol,
          0
        ); console.log(`Vault deployed to ${vault.address}`);

        strategy = await Strategy.deploy(
          targetFarm.lpToken.address,
          targetFarm.pid,
          vault.address,
          pools.treasury,
        ); console.log(`Strategy deployed to ${strategy.address}`);

        await vault.initialize(strategy.address);
        console.log(`Vault initialized`);
      }

      async function massApprove() {
        await approve(user1);
        await approve(user2);
        await approve(user3);
        await approve(user4);
      }

      async function approve(signer) {
        console.log("other approve");
        await targetToken.connect(signer).approve(vault.address, ethers.utils.parseEther("100000000000"));
        console.log("other approved");
      }

      async function advanceTime(amount) {
        await ethers.provider.send("evm_increaseTime", amount);
      }

      async function advanceBlocks(amount) {
        for(let i = 0; i<amount; i++) {
          await ethers.provider.send("evm_mine");
        }
      }

      async function depositAndLog(signer, amount) {
        const signerAddress = await signer.getAddress();
        console.log(`++++++++++${signer}++++++++++++++`);
        let initialTTBalance = await targetToken.balanceOf(signerAddress);
        console.log(`${signerAddress} Target Token Balance: ${initialTTBalance.toString()}`);
        let initialVaultBalance = await vault.balance();
        console.log(`Vault Balance Before Deposit: ${initialVaultBalance.toString()}`);
        let initialShareBalance = await vault.balanceOf(signerAddress);
        console.log(`Share Balance Before Deposit: ${initialBalance.toString()}`);
        let tx = await vault.connect(signer).deposit(amount);
        await tx.wait();
        let vaultBalanceAfter = await vault.balance();
        console.log(`Vault Balance After Deposit: ${vaultBalanceAfter.toString}`);
        let shareBalanceAfter = await vault.balanceOf(signerAddress);
        console.log(`Share Balance After Deposit: ${balanceAfter.toString()}`);
        let ttBalanceAfter = await targetToken.balanceOf(signerAddress);
        console.log(`${signerAddress} Target Token Balance: ${ttBalanceAfter.toString()}`);
        console.log(`++++++++++++++++++++++++++++++++++`);
      }

      //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
      await deploy(pools.steakv2.farms[0]);
      console.log(vault.address);
      await massApprove();
      await moneyBoost();
      await moneyBlast(
        spiritswap,
        spiritFactory,
        tokens.ifusd,
        tokens.steak,
        ethers.utils.parseEther("10")
      );
      console.log("4");

      await depositAndLog(user1, ethers.utils.parseEther("10000"));
    });
  });
});
