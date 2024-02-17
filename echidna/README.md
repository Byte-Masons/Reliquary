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