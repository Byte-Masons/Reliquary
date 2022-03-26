import {Oath, NFTDescriptor, Sigmoid, Constant} from './../types';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {network, ethers, waffle, artifacts} from 'hardhat';
import {expect} from 'chai';
import {Artifact} from 'hardhat/types';
import {deployContract} from 'ethereum-waffle';
import {Signer} from 'ethers';

const {deployChef, deployNFTDescriptor, getPoolCount, addPool, viewPoolInfo, getPositionInfo} = require('../src/Reliquary.js');

let superAdmin: SignerWithAddress, alice: SignerWithAddress, bob: SignerWithAddress, operator: SignerWithAddress;
let lp: Oath, oath: Oath;
let curve: Sigmoid;

const deployOath = async (deployer: Signer, tokenName: string, tokenSymbol: string) => {
  const artifact: Artifact = await artifacts.readArtifact('Oath');
  const contract: Oath = <Oath>await deployContract(deployer, artifact, [tokenName, tokenSymbol]);
  return contract;
};

const deployConstantEmissionSetter = async (deployer: Signer) => {
  const artifact: Artifact = await artifacts.readArtifact('Constant');
  const contract: Constant = <Constant>await deployContract(deployer, artifact);
  return contract;
};

const deploySigmoidCurve = async (deployer: Signer) => {
  const artifact: Artifact = await artifacts.readArtifact('Sigmoid');
  const contract: Sigmoid = <Sigmoid>await deployContract(deployer, artifact);
  return contract;
};

describe('Reliquary', function () {
  beforeEach(async function () {
    [superAdmin, alice, bob, operator] = await ethers.getSigners();

    oath = await deployOath(superAdmin, 'Oath', 'OATH');
    lp = await deployOath(superAdmin, 'LP Token', 'LPT');
    await lp.mint(superAdmin.address, ethers.utils.parseEther('1000'));

    curve = await deploySigmoidCurve(superAdmin);

    const nftDescriptor: NFTDescriptor = await deployNFTDescriptor();
    const emissionSetter: Constant = await deployConstantEmissionSetter(superAdmin);
    this.chef = await deployChef(oath.address, nftDescriptor.address, emissionSetter.address);

    const operatorRole: String = await this.chef.OPERATOR();
    await this.chef.grantRole(operatorRole, operator.address);
    await oath.mint(this.chef.address, ethers.utils.parseEther('100000000'));
    //const Rewarder = await ethers.getContractFactory("RewarderMock");
    //this.rewarder = await Rewarder.deploy(1, oath.address, this.chef.address);
  });

  describe('PoolLength', function () {
    it('PoolLength should execute', async function () {
      await addPool(
        operator,
        this.chef.address,
        100,
        lp.address,
        ethers.constants.AddressZero,
        curve.address,
        'LP Token',
        false,
      );
      expect(await getPoolCount(this.chef.address)).to.be.equal(1);
    });
  });

  describe('ModifyPool', function () {
    it('Should emit event LogPoolModified', async function () {
      await addPool(
        operator,
        this.chef.address,
        100,
        lp.address,
        ethers.constants.AddressZero,
        curve.address,
        'LP Token',
        false,
      );
      await expect(
        this.chef.connect(operator).modifyPool(0, 100, ethers.constants.AddressZero, curve.address, 'LP Token 2', false, false),
      ).to.emit(this.chef, 'LogPoolModified');
      await expect(this.chef.connect(operator).modifyPool(0, 100, oath.address, curve.address, 'LP Token 2', false, true))
        .to.emit(this.chef, 'LogPoolModified')
        .withArgs(0, 100, oath.address, curve.address, false);
    });

    it('Should revert if invalid pool', async function () {
      await expect(
        this.chef.connect(operator).modifyPool(0, 100, ethers.constants.AddressZero, curve.address, 'LP Token', false, false),
      ).to.be.reverted;
    });

    it('Should revert if role not authorized', async function () {
      await expect(this.chef.modifyPool(0, 100, ethers.constants.AddressZero, curve.address, 'LP Token', false, false)).to.be
        .reverted;
    });
  });

  describe('PendingOath', function () {
    it('PendingOath should equal ExpectedOath', async function () {
      await addPool(
        operator,
        this.chef.address,
        1,
        lp.address,
        ethers.constants.AddressZero,
        curve.address,
        'LP Token',
        false,
      );
      await lp.approve(this.chef.address, ethers.utils.parseEther('1000'));
      await this.chef.createRelicAndDeposit(alice.address, 0, ethers.utils.parseEther('1'));
      await network.provider.send('evm_increaseTime', [31557600]);
      await network.provider.send('evm_mine');
      await this.chef.updatePool(0);
      await network.provider.send('evm_mine');
      const firstOwnedToken = await this.chef.tokenOfOwnerByIndex(alice.address, 0);
      const pendingOath = await this.chef.pendingOath(firstOwnedToken);
      expect(pendingOath).to.equal(ethers.utils.parseEther('3155760.2')); //(31557600 + 2)secs * 1000ms * 1e14
    });
  });

  describe('MassUpdatePools', function () {
    it('Should call updatePool', async function () {
      await addPool(
        operator,
        this.chef.address,
        1,
        lp.address,
        ethers.constants.AddressZero,
        curve.address,
        'LP Token',
        false,
      );
      await network.provider.send('evm_mine');
      await expect(this.chef.massUpdatePools([0])).to.emit(this.chef, 'LogUpdatePool');
    });

    it('Updating invalid pools should fail', async function () {
      await expect(this.chef.massUpdatePools([0, 1000, 10000])).to.be.reverted;
    });
  });

  describe('AddPool', function () {
    it('Should add pool with reward token multiplier', async function () {
      await expect(
        this.chef.connect(operator).addPool(10, lp.address, ethers.constants.AddressZero, curve.address, 'LP Token', false),
      )
        .to.emit(this.chef, 'LogPoolAddition')
        .withArgs(0, 10, lp.address, ethers.constants.AddressZero, curve.address, false);
    });
  });

  describe('UpdatePool', function () {
    it('Should emit event LogUpdatePool', async function () {
      await addPool(
        operator,
        this.chef.address,
        1,
        lp.address,
        ethers.constants.AddressZero,
        curve.address,
        'LP Token',
        false,
      );
      await network.provider.send('evm_mine');
      await expect(this.chef.updatePool(0))
        .to.emit(this.chef, 'LogUpdatePool')
        .withArgs(
          0,
          (
            await this.chef.poolInfo(0)
          ).lastRewardTime,
          await lp.balanceOf(this.chef.address),
          (
            await this.chef.poolInfo(0)
          ).accOathPerShare,
        );
    });
  });

  describe('Deposit', function () {
    it('Depositing 1', async function () {
      await addPool(
        operator,
        this.chef.address,
        10,
        lp.address,
        ethers.constants.AddressZero,
        curve.address,
        'LP Token',
        false,
      );
      await lp.approve(this.chef.address, 10);
      await expect(this.chef.createRelicAndDeposit(alice.address, 0, 1))
        .to.emit(this.chef, 'Deposit')
        .withArgs(superAdmin.address, 0, 1, alice.address, 0);
    });

    it('Depositing into non-existent pool should fail', async function () {
      await expect(this.chef.createRelicAndDeposit(alice.address, 1001, 1)).to.be.reverted;
    });
  });

  describe('Withdraw', function () {
    it('Withdraw 1', async function () {
      await addPool(
        operator,
        this.chef.address,
        10,
        lp.address,
        ethers.constants.AddressZero,
        curve.address,
        'LP Token',
        false,
      );
      await lp.approve(this.chef.address, 10);
      await this.chef.createRelicAndDeposit(alice.address, 0, 1);
      const firstOwnedToken = await this.chef.tokenOfOwnerByIndex(alice.address, 0);
      await expect(this.chef.connect(alice).withdraw(1, firstOwnedToken))
        .to.emit(this.chef, 'Withdraw')
        .withArgs(alice.address, 0, 1, alice.address, firstOwnedToken);
    });
  });

  describe('Harvest', function () {
    it('Should give back the correct amount of OATH', async function () {
      await addPool(
        operator,
        this.chef.address,
        1,
        lp.address,
        ethers.constants.AddressZero,
        curve.address,
        'LP Token',
        false,
      );
      await lp.approve(this.chef.address, ethers.utils.parseEther('1000'));
      await this.chef.createRelicAndDeposit(alice.address, 0, ethers.utils.parseEther('1'));
      await network.provider.send('evm_increaseTime', [302400]);
      await network.provider.send('evm_mine');
      const nftA = await this.chef.tokenOfOwnerByIndex(alice.address, 0);
      //await this.chef.deposit(ethers.utils.parseEther('100'), nftA);
      await this.chef.createRelicAndDeposit(bob.address, 0, ethers.utils.parseEther('100'));
      await network.provider.send('evm_increaseTime', [302400]);
      await network.provider.send('evm_mine');
      const nftB = await this.chef.tokenOfOwnerByIndex(bob.address, 0);

      await this.chef.connect(alice).harvest(nftA);
      await this.chef.connect(bob).harvest(nftB);
      const timestamp = parseInt((await network.provider.send('eth_getBlockByNumber', ['latest', false])).timestamp);
      const averageEntry = Math.floor((await this.chef.poolInfo(0))[3] / 1000);
      console.log("curve average: ", (await curve.curve(timestamp - averageEntry)).toString());
      console.log("curveA: ", (await this.chef.curved(nftA)).toString());
      console.log("curveB: ", (await this.chef.curved(nftB)).toString());
      const balanceA = await oath.balanceOf(alice.address);
      const balanceB = await oath.balanceOf(bob.address);
      console.log("balanceA: ", balanceA.toString());
      console.log("balanceB: ", balanceB.toString());
      //expect(balanceA).to.equal(ethers.BigNumber.from('1593502675247524752000000')); //(31557600 + 1)secs * 1000ms * 1e14
      //expect(balanceB).to.equal(ethers.BigNumber.from('1562257623762376100000000')); //(31557600 + 1)secs * 1000ms * 1e14
      console.log("positionA: ", await getPositionInfo(this.chef.address, nftA));
      console.log("positionB: ", await getPositionInfo(this.chef.address, nftB));
      console.log("poolInfo: ", await viewPoolInfo(this.chef.address, 0));
    });
  });

  describe('EmergencyWithdraw', function () {
    it('Should emit event EmergencyWithdraw', async function () {
      await addPool(
        operator,
        this.chef.address,
        10,
        lp.address,
        ethers.constants.AddressZero,
        curve.address,
        'LP Token',
        false,
      );
      await lp.approve(this.chef.address, 10);
      await this.chef.createRelicAndDeposit(alice.address, 0, 1);
    });
  });
});
