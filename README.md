# Reliquary V2

![Reliquary](header.png "Reliquary")

> Designed and written by [Justin Bebis](https://twitter.com/0xBebis_), Zokunei and [Beirao](https://twitter.com/0xBeirao), with help from [Goober](https://twitter.com/0xGoober) and the rest of the [Byte Masons](https://twitter.com/ByteMasons) crew.

---

Reliquary is a smart contract system that is designed to improve outcomes of incentive distribution by giving users and developers fine grained control over their investments and rewards. It accomplishes this with the following features:

1. Emits tokens based on the maturity of a user's investment, separated in tranches.
2. Binds variable emission rates to a base emission curve designed by the developer for predictable emissions.
3. Supports deposits and withdrawals along with these variable rates, which has historically been impossible.
4. Issues a 'financial NFT' to users which represents their underlying positions, able to be traded and leveraged without removing the underlying liquidity.
5. Can emit multiple types of rewards for each investment as well as handle complex reward mechanisms based on deposit and withdrawal.

By binding tokens to a base emission rate you not only gain the advantage of a predictable emission curve, but you're able
to get extremely creative with the Curve contracts you write. Whether this be a sigmoid curve, a square root curve, or a
random curve, you can codify the user behaviors you'd like to promote.

Please reach out to zokunei@bytemasons.com to report bugs or other funky behavior. We will proceed with various stages of production
testing in the coming weeks.

## V2 update notes

1. **Maturity Evolution Curves**: We have replaced the previous level evolution mechanism with curves to provide more flexibility and precision. The available curve options are:
   - Linear
   - Linear Plateau
   - Polynomial Plateau

2. **Scalable 'Level' Number**: The 'Level' number now scales with an O(1) complexity, ensuring consistent performance as the system grows.

3. **Multi-Rewards with Rolling Rewarders**: The V2 update now enables the possibility of multiple rewards with the rolling rewarders.

4. **ABI Simplification**: We have simplified ABI to streamline the interaction between the smart contracts and the user interface.

5. **Gas Optimization**: The V2 update brings a 20% reduction in gas consumption, resulting in lower transaction fees and improved efficiency.

6. **Bug Fixes**: We have addressed bugs identified in the previous version (see audit/ for more details).

7. **Code Clean-up, Formatting, and Normalization**: The codebase has undergone a thorough clean-up, formatting, and normalization process to improve readability and maintainability.

## Installation

This is a Foundry project. Get Foundry from [here](https://github.com/foundry-rs/foundry).

Please run the following command in this project's root directory to enable pre-commit testing:

```bash
ln -s ../../pre-commit .git/hooks/pre-commit
```

## Quick start

### Env setup
```bash
mv .env.example .env
```
Fill your `ETHERSCAN_API_KEY` in the `.env`.

### Foundry
```bash
forge install
forge test
```

### Echidna
```bash
echidna test/echidna/ReliquaryProperties.sol  --contract ReliquaryProperties --config test/echidna/config1_fast.yaml
```

## Typing conventions

### Variables

-   storage: `x`
-   memory/stack: `x_`
-   function params: `_x`
-   contracts/events/structs: `MyContract`
-   errors: `MyContract__ERROR_DESCRIPTION`
-   public/external functions: `myFunction()`
-   internal/private functions: `_myFunction()`
-   comments: "This is a comment to describe the variable `amount`."

### Nat Specs

```js
/**
 * @dev Internal function called whenever a position's state needs to be modified.
 * @param _amount Amount of poolToken to deposit/withdraw.
 * @param _relicId The NFT ID of the position being updated.
 * @param _kind Indicates whether tokens are being added to, or removed from, a pool.
 * @param _harvestTo Address to send rewards to (zero address if harvest should not be performed).
 * @return poolId_ Pool ID of the given position.
 * @return received_ Amount of reward token dispensed to `_harvestTo` on harvest.
 */
```

### Formating

Please use `forge fmt` before commiting.

## TODOs

-   NFT Desccriptor needs to be ajusted to curve
-   Tests PolynomialCurves
