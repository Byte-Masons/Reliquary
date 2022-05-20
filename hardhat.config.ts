require('dotenv').config();

import {HardhatUserConfig} from 'hardhat/config';
import '@typechain/hardhat';
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-waffle';
import '@nomiclabs/hardhat-solhint';
import 'hardhat-gas-reporter';

import 'hardhat-deploy';
import 'hardhat-deploy-ethers';

// require("./secrets.json");

const { devAccount, reaperAccount, testAccount, ftmScan } = require('./secrets.json');

const config: HardhatUserConfig = {
  networks: {
    hardhat: {
      //forking: {
        //url: 'https://rpc.ftm.tools/',
        //blockNumber: 11238828,
        // accounts: [reaperAccount]
      //},
    },
    test: {
      url: 'https://rpc.testnet.fantom.network/',
      accounts: [testAccount]
    },
    opera: {
      url: 'https://rpc.ftm.tools/',
      // accounts: [testAccount]
    },
  },
  // etherscan: {
  // apiKey: ftmScan
  // },
  solidity: {
    compilers: [
      {
        version: '0.5.16',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: '0.8.13',
        settings: {
          //viaIR: true,
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  paths: {
    sources: './contracts',
    tests: './test',
    cache: './cache',
    artifacts: './artifacts',
  },
  typechain: {
    outDir: 'types',
    target: 'ethers-v5',
  },
  gasReporter: {
    currency: 'USD',
    token: 'FTM',
    coinmarketcap: process.env.COINMARKETCAP,
  },
  mocha: {
    timeout: 200000,
  },
};

export default config;
