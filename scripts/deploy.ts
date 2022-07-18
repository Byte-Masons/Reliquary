import { ContractFactory, providers } from 'ethers';
const provider = require('eth-provider');
import { artifacts } from 'hardhat';

async function main() {
  const frame: any = new providers.Web3Provider(provider());

  /*const TestToken: any = await artifacts.readArtifact('TestToken');
  const testOath: any = await ContractFactory.fromSolidity(TestToken, frame.getSigner());
  const deployedOath = await testOath.deploy("Test OATH", "TOATH", 18);*/

  const Constant: any = await artifacts.readArtifact('Constant');
  const constant: any = await ContractFactory.fromSolidity(Constant, frame.getSigner());
  const deployedConstant = await constant.deploy();

  const Reliquary: any = await artifacts.readArtifact('Reliquary');
  const reliquary: any = await ContractFactory.fromSolidity(Reliquary, frame.getSigner());
  const deployedReliquary: any = await reliquary.deploy('0x21Ada0D2aC28C3A5Fa3cD2eE30882dA8812279B6', deployedConstant.address);

  const NFTDescriptor: any = await artifacts.readArtifact('NFTDescriptorSingle4626');
  const nftDescriptor: any = await ContractFactory.fromSolidity(NFTDescriptor, frame.getSigner());
  const deployedNFTDescriptor: any = await nftDescriptor.deploy(deployedReliquary.address);

  const DepositHelper: any = await artifacts.readArtifact('DepositHelper');
  const depositHelper: any = await ContractFactory.fromSolidity(DepositHelper, frame.getSigner());
  const deployedDepositHelper: any = await depositHelper.deploy('0x90fEC9587624dC4437833Ef3C34C218996B8AB98');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
