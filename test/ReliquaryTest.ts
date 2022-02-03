import {Oath, NFTDescriptor, EighthRoot} from './../types';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {network, ethers, waffle, artifacts} from 'hardhat';
import {expect} from 'chai';
import {Artifact} from 'hardhat/types';
import {deployContract} from 'ethereum-waffle';
import {Signer} from 'ethers';

const {deployChef, getPoolCount, addPool} = require('../src/Reliquary.js');

let owner: SignerWithAddress, alice: SignerWithAddress, bob: SignerWithAddress;
let lp: Oath, oath: Oath;
let curve: EighthRoot;

const deployOath = async (deployer: Signer, tokenName: string, tokenSymbol: string) => {
  const artifact: Artifact = await artifacts.readArtifact('Oath');
  const contract: Oath = <Oath>await deployContract(deployer, artifact, [tokenName, tokenSymbol]);
  return contract;
};

const deployNFTDescriptor = async (deployer: Signer) => {
  const artifact: Artifact = await artifacts.readArtifact('NFTDescriptor');
  const contract: NFTDescriptor = <NFTDescriptor>await deployContract(deployer, artifact);
  return contract;
};

const deployEighthRootCurve = async (deployer: Signer) => {
  const artifact: Artifact = await artifacts.readArtifact('Sigmoid');
  const contract: EighthRoot = <EighthRoot>await deployContract(deployer, artifact);
  return contract;
};

describe('Reliquary', function () {
  beforeEach(async function () {
    [owner, alice, bob] = await ethers.getSigners();

    oath = await deployOath(owner, 'Oath', 'OATH');
    lp = await deployOath(owner, 'LP Token', 'LPT');
    await lp.mint(owner.address, ethers.utils.parseEther('1000'));

    curve = await deployEighthRootCurve(owner);

    const nftDescriptor: NFTDescriptor = await deployNFTDescriptor(owner);
    this.chef = await deployChef(oath.address, nftDescriptor.address);
    await oath.mint(this.chef.address, ethers.utils.parseEther('100000000'));
    //const Rewarder = await ethers.getContractFactory("RewarderMock");
    //this.rewarder = await Rewarder.deploy(1, oath.address, this.chef.address);
  });

  describe('PoolLength', function () {
    it('PoolLength should execute', async function () {
      await addPool(this.chef.address, 100, lp.address, ethers.constants.AddressZero, curve.address);
      expect(await getPoolCount(this.chef.address)).to.be.equal(1);
    });
  });

  describe('ModifyPool', function () {
    it('Should emit event LogPoolModified', async function () {
      await addPool(this.chef.address, 100, lp.address, ethers.constants.AddressZero, curve.address);
      await expect(this.chef.modifyPool(0, 100, ethers.constants.AddressZero, curve.address, false, false)).to.emit(
        this.chef,
        'LogPoolModified',
      );
      await expect(this.chef.modifyPool(0, 100, oath.address, curve.address, true, false))
        .to.emit(this.chef, 'LogPoolModified')
        .withArgs(0, 100, oath.address, curve.address);
    });

    it('Should revert if invalid pool', async function () {
      await expect(this.chef.modifyPool(0, 100, ethers.constants.AddressZero, curve.address, false, false)).to.be
        .reverted;
    });
  });

  describe('PendingOath', function () {
    it('PendingOath should equal ExpectedOath', async function () {
      await addPool(this.chef.address, 1, lp.address, ethers.constants.AddressZero, curve.address);
      await lp.approve(this.chef.address, ethers.utils.parseEther('1000'));
      await this.chef.createRelicAndDeposit(alice.address, 0, ethers.utils.parseEther('1'));
      await network.provider.send('evm_increaseTime', [31557600]);
      await network.provider.send('evm_mine');
      await this.chef.updatePool(0);
      await network.provider.send('evm_mine');
      const firstOwnedToken = await this.chef.tokenOfOwnerByIndex(alice.address, 0);
      const imageB64: String = String(
        Buffer.from((
        await this.chef.tokenURI(firstOwnedToken)).
        replace('data:application/json;base64,', ''),
        'base64').toString().
        split(',').pop());
      const html: String = Buffer.from(imageB64.substr(0, imageB64.length - 2), 'base64').toString();
      console.log(html);
      const pendingOath = await this.chef.pendingOath(firstOwnedToken);
      expect(pendingOath).to.equal(ethers.BigNumber.from('3155760200000000000')); //(31557600 + 2) * 100000000000
    });
  });

  describe('MassUpdatePools', function () {
    it('Should call updatePool', async function () {
      await addPool(this.chef.address, 1, lp.address, ethers.constants.AddressZero, curve.address);
      await network.provider.send('evm_mine');
      await expect(this.chef.massUpdatePools([0])).to.emit(this.chef, 'LogUpdatePool');
    });

    it('Updating invalid pools should fail', async function () {
      await expect(this.chef.massUpdatePools([0, 1000, 10000])).to.be.reverted;
    });
  });

  describe('AddPool', function () {
    it('Should add pool with reward token multiplier', async function () {
      await expect(this.chef.addPool(10, lp.address, ethers.constants.AddressZero, curve.address))
        .to.emit(this.chef, 'LogPoolAddition')
        .withArgs(0, 10, lp.address, ethers.constants.AddressZero, curve.address);
    });
  });

  describe('UpdatePool', function () {
    it('Should emit event LogUpdatePool', async function () {
      await addPool(this.chef.address, 1, lp.address, ethers.constants.AddressZero, curve.address);
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
      await addPool(this.chef.address, 10, lp.address, ethers.constants.AddressZero, curve.address);
      await lp.approve(this.chef.address, 10);
      await expect(this.chef.createRelicAndDeposit(alice.address, 0, 1))
        .to.emit(this.chef, 'Deposit')
        .withArgs(owner.address, 0, 1, alice.address, 0);
    });

    it('Depositing into non-existent pool should fail', async function () {
      await expect(this.chef.createRelicAndDeposit(alice.address, 1001, 1)).to.be.reverted;
    });
  });

  describe('Withdraw', function () {
    it('Withdraw 1', async function () {
      await addPool(this.chef.address, 10, lp.address, ethers.constants.AddressZero, curve.address);
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
      await addPool(this.chef.address, 1, lp.address, ethers.constants.AddressZero, curve.address);
      await lp.approve(this.chef.address, ethers.utils.parseEther('1000'));
      await this.chef.createRelicAndDeposit(alice.address, 0, ethers.utils.parseEther('1'));
      await network.provider.send('evm_increaseTime', [31557600]);
      await network.provider.send('evm_mine');
      const firstOwnedToken = await this.chef.tokenOfOwnerByIndex(alice.address, 0);

      await this.chef.connect(alice).harvest(firstOwnedToken);
      const balance = await oath.balanceOf(alice.address);
      expect(balance).to.equal(ethers.BigNumber.from('3155760100000000000')); // (31557600 + 1) * 100000000000
    });
  });

  describe('EmergencyWithdraw', function () {
    it('Should emit event EmergencyWithdraw', async function () {
      await addPool(this.chef.address, 10, lp.address, ethers.constants.AddressZero, curve.address);
      await lp.approve(this.chef.address, 10);
      await this.chef.createRelicAndDeposit(alice.address, 0, 1);
    });
  });
});
