# Reliquary

![Reliquary](header.png "Reliquary")

> Designed and Written by [Justin Bebis](https://twitter.com/0xBebis_) with help from Zokunei, [Goober](https://twitter.com/0xGoober), and the rest of the [Byte Masons](https://twitter.com/ByteMasons) crew
---
Reliquary is a heavily upgraded [MasterchefV2](https://docs.sushi.com/products/masterchef-v2) contract that is designed to:
1) Emit tokens based on an arbitrary curve dictated within a "Curve" library (stored as an address within each pool)
2) Bind that curve to a base emission rate (The curve will be set by your earliest pool entrants)
3) Push users down the curve when they deposit or withdraw their tokens based on the weight of their deposit/withdrawal
4) Move the average curve of the entire pool up and down as people enter and exit the pools
5) Issue an NFT derivative that represents your positions within the farm

By binding tokens to a base emission rate, you not only gain the advantage of a predictable emission curve, but you're able
to get extremely creative with the Curve contracts you write. Whether this be a sigmoid curve, a square root curve, or a
random curve, you can codify the user behaviors you'd like to promote.

Things to watch out for:

Because we bind the curve to a standard emission rate, it will be set by the earliest entrants of your pool. This means
that initial depositors will receive the maximum amount possible at any given time. This is fine behavior for the most part,
as it ensures new competition for emissions doesn't hurt your early entrants, but in some cases you may want to promote equanamity.
To achieve this, you need simply design a curve that is relatively flat at the start - our sigmoid works just fine for this.
Bell curves or simple linear graphs can accomplish the same. We have considered adding it to our yield aggregator's front-end
before making direct UI deposits available so that the curve can be set collectively by Reaper users.

Also, something to note is the total average recorded in the pool is moved up and down the curve based on deposits
and withdrawals agnostic to the user performing the deposit or withdrawal. While users are individually penalized for
their movement in and out, the pool as a whole seeks to achieve 'zero-sum' behavior regardless of the context of each
interaction. This will rarely cause issues, but is worth remembering when doing customer service.

Please reach out to zokunei@bytemasons.com to report bugs or other funky behavior. We will proceed with various stages of production
testing in the coming weeks.


## Installation
This is a `Hardhat` project which requires a specific node version. We have provided an `.nvmrc` file which shows the current required version of node. You can install manually or via [nvm](https://github.com/nvm-sh/nvm) by using the command.
```bash
nvm use
```


All dependencies are managed by `npm`, you can install the project using the command
```bash
npm install
```


## Testing

We have `hardhat` test coverage in the file `test/ReliquaryTest.ts`, you will need to ensure the contracts have been compiled before running so please use the commands:

```bash
npm run build
npm run test
```

## Chef tester
We also have an `End to End` test script that tests the MasterChef works as intended. 

```bash
npx hardhat run scripts/ChefTester.js
```
