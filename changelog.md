# Packages added

- `@typechain/ethers-v5` for typechain support
- `@typechain/hardhat` for typechain support
- `dotenv` to load `.env` files
- `hardhat-gas-reporter` for gas reporting
- `solhint` for solhint support
- `solhint-plugin-prettier` for solhint prettier
- `@nomiclabs/hardhat-solhint` for solhint hardhat

- `@types/chai` typescript support
- `@types/mocha` types
- `@types/node` types
- `ts-node` typescript support
- `typechain` typescript support
- `typescript` typescript support

# Configurations & Others

- Removed unused solidity compiler version from hardhat config
- configured gas reporter to work in FTM/USD
- created `.env.sample`
- added `.solhint.json` configuration
- added `.prettierrc` configuration
- migrated hardhat config to typescript
- added basic `tsconfig.json`

# Prettier

I've added my prettier rules, these are totally a personal preference so please bear in mind with that.
I've not applied them to `.sol` files just because I didn't want to create merge conflicts atm.

# Further improvements

Before doing other changes would be important to understand where these things are used and what impact they could have

- move ETHSCAN_APIKEY to `.env`
- move `*.json` to a proper folder structure
- migrate current `*.js` to typescript
- update tests to use all typescript interfaces
- add `@nomiclabs/hardhat-etherscan`
