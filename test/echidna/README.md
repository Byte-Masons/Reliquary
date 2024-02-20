## Echidna

Echidna is a program designed for fuzzing/property-based testing of Ethereum smart contracts. Please refer to the doc for [installation](https://github.com/crytic/echidna#installation).

Run with:

```sh
echidna test/echidna/ReliquaryProperties.sol  --contract ReliquaryProperties --config test/echidna/config1_fast.yaml
```

You can fine in `/echidna` 3 config files to run the fuzzer:

-   1< min | `config1_fast.yaml`
-   5< min | `config2_slow.yaml`
-   50 min | `config3_inDepth.yaml`

## Invariants

-   ✅ A user should never be able to withdraw more than deposited.
-   ✅ No `position.entry` should be greater than `block.timestamp`.
-   ✅ The sum of all `position.amount` should never be greater than total deposit.
-   ✅ The sum of all `allocPoint` should be equal to `totalAllocpoint`.
-   ✅ The total reward harvested and pending should never be greater than the total emission rate.
-   ✅ `emergencyWithdraw` should burn position rewards.
