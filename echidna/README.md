## Echidna

Echidna is a program designed for fuzzing/property-based testing of Ethereum smart contracts. Please refer to the doc for [installation](https://github.com/crytic/echidna#installation).

Run with:

```sh
echidna echidna/ReliquaryProperties.sol  --contract ReliquaryProperties --config echidna/config1_fast.yaml
```

You can fine in `/echidna` 3 config files to run the fuzzer:

-   1< min | `config1_fast.yaml`
-   5< min | `config2_slow.yaml`
-   50 min | `config3_inDepth.yaml`
  
## Invariants

- ✅ A user should never be able to withdraw more than deposited.
- ✅ No position.entry should be greater than block.timestamp.
- ✅ The sum of all position.amount should never be greater than total deposit.
- ✅ The sum of balances in levels should never be greater than total deposit.
- ✅ All arrays defining pools should be equal in size.
- ✅ The sum of all allocPoint must be equal to totalAllocpoint.
- ✅ The total reward harvested and pending should never be greater than the total emission rate.
- ✅ EmergencyWithdraw should burn position rewards.
- ✅ A position amount should never be greater than the level.balance deposited at the position level.
- ✅ `pool.totalLpSupplied` should remain equal to the sum of all `levelInfo.balance * levelInfo.multipliers`.