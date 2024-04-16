# 1. About cergyk

cergyk is a smart contract security expert, highly ranked accross a variety of audit contest platforms. He has helped multiple protocols in preventing critical exploits since 2022.

# 2. Introduction

A time-boxed security review of the `Reliquary V2` protocol was done by cergyk, with a focus on the security aspects of the application's smart contracts implementation.

# 3. Disclaimer
A smart contract security review can never verify the complete absence of vulnerabilities. This is
a time, resource and expertise bound effort aimed at finding as many vulnerabilities as
possible. We can not guarantee 100% security after the review or even if the review will find any
problems with your smart contracts. Subsequent security reviews, bug bounty programs and on-
chain monitoring are strongly recommended.

# 4. About Reliquary V2

Reliquary is an improvement of the famous MasterChef contract. The goal is to distribute a reward token proportional to the amount of a user's deposit. The protocol owner can credit the contract with the reward token and set the desired issuance per second.

Compared to Masterchef, the `Reliquary V2` contract offers more flexibility and customization:

1. Emits tokens based on the maturity of a user's investment. 
2. Binds variable emission rates to a base emission curve designed by the developer for predictable emissions.
3. Supports deposits and withdrawals along with these variable rates.
4. Issues a 'financial NFT' to users which represents their underlying positions, able to be traded and leveraged without removing the underlying liquidity.
5. Can emit multiple types of rewards for each investment, as well as handle complex reward mechanisms based on deposit and withdrawal.

The novelty implemented in this iteration is the addition of non-linear (polynomial) unlocking curves.

# 5. Security Assessment Summary

***review commit hash* - [a3f686e4](https://github.com/beirao/Reliquary/commit/a3f686e4609f58bc5665c80f3f97eb9fe7c6d668)**

***fixes review commit hash* - [f262a1eb](https://github.com/beirao/Reliquary/commit/f262a1ebe9c45d7514028604152a702f8f6470b5)**

## Deployment chains

- All EVM chains

## Scope

The following smart contracts were in scope of the audit: (total : 975 SLoC)

- [`Reliquary.sol`](https://github.com/beirao/Reliquary/blob/a3f686e4609f58bc5665c80f3f97eb9fe7c6d668/contracts/Reliquary.sol)
- [`ParentRollingRewarder.sol`](https://github.com/beirao/Reliquary/blob/a3f686e4609f58bc5665c80f3f97eb9fe7c6d668/contracts/rewarders/ParentRollingRewarder.sol)
- [`RollingRewarder.sol`](https://github.com/beirao/Reliquary/blob/a3f686e4609f58bc5665c80f3f97eb9fe7c6d668/contracts/rewarders/RollingRewarder.sol)
- [`ReliquaryLogic.sol`](https://github.com/beirao/Reliquary/blob/a3f686e4609f58bc5665c80f3f97eb9fe7c6d668/contracts/libraries/ReliquaryLogic.sol)
- [`LinearCurve.sol`](https://github.com/beirao/Reliquary/blob/a3f686e4609f58bc5665c80f3f97eb9fe7c6d668/contracts/curves/LinearCurve.sol)
- [`LinearPlateauCurve.sol`](https://github.com/beirao/Reliquary/blob/a3f686e4609f58bc5665c80f3f97eb9fe7c6d668/contracts/curves/LinearPlateauCurve.sol)
- [`PolynomialPlateauCurve.sol`](https://github.com/beirao/Reliquary/blob/a3f686e4609f58bc5665c80f3f97eb9fe7c6d668/contracts/curves/PolynomialPlateauCurve.sol)

# 6. Executive Summary

A security review of the contracts of Reliquary has been conducted during **5 days**.
A total of **14 findings** have been identified and can be classified as below:

### Protocol
| | Details|
|---------------|--------------------|
| **Protocol Name** | Reliquary V2 |
| **Repository**    | [Reliquary V2](https://github.com/beirao/Reliquary/blob/a3f686e4609f58bc5665c80f3f97eb9fe7c6d668/contracts) |
| **Date**          | April 2nd 2024 - April 8th 2024 |
| **Type**          | Rewards distributor |

### Findings Count
| Severity  | Findings Count |
|-----------|----------------|
| Critical  |     0           |
| High      |     1           |
| Medium    |     5           |
| Low       |     3           |
| Info/Gas       |     4         |
| **Total findings**| 13         |


# 7. Findings summary
| Findings |
|-----------|
|H-1 Wrong entry calculation in Reliquary::shift()|
|M-1 Rounding in _updateEntry during deposit enables to increase positions without changing entry
|M-2 Reliquary::addPool remove part of the existing rewards|
|M-3 Reliquary::setEmissionRate does not update pools|
|M-4 Reliquary::shift unfavorable rounding can be used to increase position level when shifting from mature position|
|M-5 Linear average for entry can be gamed in case of non-linear curve functions|
|L-1 Rewarder initialization Dos by front-run|
|L-2 deposit and shift/merge have a slightly different average  formula|
|L-3 When a pool is updated and totalLpSupply == 0 the rewards are lost for the pool|
| INFO-1 Change condition to require for readability |
| INFO-2 Reentrancy available in burn() |
| INFO-3 Reliquary::burn() doesn't clean positionForId mapping |
| GAS-1 Loading the whole PoolInfo struct when using a specific parameter |

# 8. Findings

## H-1 Wrong entry calculation in Reliquary::shift()

### Vulnerability detail

The average entry point is wrongly weighted using the amount in the original `from` position, whereas only the portion `_amount` is transferred to the new `to` position and should be used to weight:

[Reliquary::shift()](https://github.com/beirao/Reliquary/blob/a3f686e4609f58bc5665c80f3f97eb9fe7c6d668/contracts/Reliquary.sol#L421-L426):
```solidity
    toPosition.entry = uint40(
        (
            vars_.fromAmount * uint256(fromPosition.entry)
                + vars_.toAmount * uint256(toPosition.entry)
        ) / (vars_.fromAmount + vars_.toAmount)
    ); // unsafe cast ok
```

As a result a malicious user can use a mature well funded position A to bump the level of a freshly created position B, by simply shifting 1 wei of A to B, and then repeat with other new positions. As a result the staking mechanism incentive is completely bypassed and rewards are unjustly overallocated to the malicious user.  

### Recommendation

use `_amount` to weight the average:

```diff
    toPosition.entry = uint40(
        (
-            vars_.fromAmount * uint256(fromPosition.entry)
+            _amount * uint256(fromPosition.entry)
                + vars_.toAmount * uint256(toPosition.entry)
-        ) / (vars_.fromAmount + vars_.toAmount)
+        ) / (_amount + vars_.toAmount)
        ) / (vars_.fromAmount + vars_.toAmount)
    ); // unsafe cast ok
```

### Fix review

Fixed by: [bdbcc133](https://github.com/beirao/Reliquary/commit/bdbcc133abae4f5b1bca8adf5fb34fc806f1af70)

## M-1 Rounding in _updateEntry during deposit enables to increase positions without changing entry

### Vulnerability detail
During a deposit on an existing position, the new entry is adjusted, but the use of rounding down can enable a user to add funds to an existing position without changing its entry:

[ReliquaryLogic::_updateEntry](https://github.com/beirao/Reliquary/blob/a3f686e4609f58bc5665c80f3f97eb9fe7c6d668/contracts/libraries/ReliquaryLogic.sol#L297-L299):
```solidity
    position.entry = uint40(
>>      entryBefore_ + (maturity_ * _findWeight(_amount, amountBefore_)) / WEIGHT_PRECISION
    ); // unsafe cast ok
```
[ReliquaryLogic::_findWeight](https://github.com/beirao/Reliquary/blob/a3f686e4609f58bc5665c80f3f97eb9fe7c6d668/contracts/libraries/ReliquaryLogic.sol#L270-L283):
```solidity
    function _findWeight(uint256 _addedValue, uint256 _oldValue)
        private
        pure
        returns (uint256 weightNew_)
    {
        if (_oldValue < _addedValue) {
            weightNew_ =
                WEIGHT_PRECISION - (_oldValue * WEIGHT_PRECISION) / (_addedValue + _oldValue);
        } else if (_addedValue < _oldValue) {
            weightNew_ = (_addedValue * WEIGHT_PRECISION) / (_addedValue + _oldValue);
        } else {
            weightNew_ = WEIGHT_PRECISION / 2;
        }
    }
```

As can be seen in the formulas above, when `_addedValue` is small compared to `_oldValue`:
```
let _oldValue = X * _addedValue
> Please note that the formula used in shift also rounds the entry down, which is not favorable to the protocol

weight = WEIGHT_PRECISION/(X+1)

so if X = _oldValue/_addedValue > _maturity, 

the following product will be rounded down to zero:
(maturity_ * _findWeight(_amount, amountBefore_)) / WEIGHT_PRECISION = (maturity * WEIGHT_PRECISION / X) / WEIGHT_PRECISION

as a result the new computed entry is entryBefore_
```

This enables an attacker to grow a position by repeatedly adding small amounts (such as `oldAmount/amount > maturity`). Each time the operation is repeated, the attacker can add slightly more, since `oldAmount` is increased.

### Recommendation
Rounding should generally be done in favor of the protocol, in this case up:

```diff
    position.entry = uint40(
-      entryBefore_ + (maturity_ * _findWeight(_amount, amountBefore_)) / WEIGHT_PRECISION
+      entryBefore_ + divUp((maturity_, _findWeight(_amount, amountBefore_), WEIGHT_PRECISION) 
    ); // unsafe cast ok
```

### Fix review

Fixed by: [45fff8b3](https://github.com/beirao/Reliquary/commit/45fff8b362df8c29fedc1eaaafd106f15e5b9cf5)

## M-2 Reliquary::addPool remove part of the existing rewards

### Vulnerability detail

Adding a new pool modifies the allocation distribution, which impacts the rewards. To distribute existing rewards fairly, Reliquary must update all of the pools before modifying the `totalAllocPoint`.

In the current version `ReliquaryLogic::_massUpdatePools` is called, but after the `totalAllocPoint` has been updated with the allocation dedicated to the new pool. This means the portion of existing rewards proportional to the allocation of the new pool will be lost.

[Reliquary::addPool](https://github.com/beirao/Reliquary/blob/a3f686e4609f58bc5665c80f3f97eb9fe7c6d668/contracts/Reliquary.sol#L124-L134):
```solidity
        // totalAllocPoint must never be zero.
        uint256 totalAlloc_ = totalAllocPoint + _allocPoint;
        if (totalAlloc_ == 0) revert Reliquary__ZERO_TOTAL_ALLOC_POINT();
        totalAllocPoint = totalAlloc_;

        //! if _curve is not increasing, allowPartialWithdrawals must be set to false.
        //! We can't check this rule since curve are defined in [0, +infinity].
    }
    // -----------------

    ReliquaryLogic._massUpdatePools(poolInfo, emissionRate, totalAllocPoint);
```

### Recommendation
Call `_massUpdatePools` before modifying `totalAllocPoint`:

```solidity
    function addPool(
        uint256 _allocPoint,
        address _poolToken,
        address _rewarder,
        ICurves _curve,
        string memory _name,
        address _nftDescriptor,
        bool _allowPartialWithdrawals
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        ReliquaryLogic._massUpdatePools(poolInfo, emissionRate, totalAllocPoint);
```

### Fix review

Fixed by: [f8767e5d](https://github.com/beirao/Reliquary/commit/f8767e5d23d9d72f82ab49f6038c9b314f2b2c9f)

## M-3 Reliquary::setEmissionRate does not update pools

### Vulnerability details
Setting a new emissionRate impacts current rewards, because pools which have not been updated will distribute more for the stale period. This will create an unequal distribution of rewards between pools which have been updated at the point when rate is modified versus the ones which have not been updated.

### Recommendation
Call `ReliquaryLogic::massUpdatePools` inside `setEmissionRate` to ensure the new emission rate does not impact pending reward distribution

```diff
function setEmissionRate(uint256 _emissionRate) external onlyRole(EMISSION_RATE) {
+   ReliquaryLogic._massUpdatePools(poolInfo, emissionRate, totalAllocPoint);
    emissionRate = _emissionRate;
    emit ReliquaryEvents.LogSetEmissionRate(_emissionRate);
}
```

### Fix review

Fixed by: [f2de3f7c](https://github.com/beirao/Reliquary/commit/f2de3f7cfb6a705f90ad3f63f6135e77a971aab0)

## M-4 Reliquary::shift unfavorable rounding can be used to increase position level when shifting from mature position

### Vulnerability details
When shifting from an existing position A to another position B, the following weighted average is applied in order to compute the new entry of B:

```
    toPosition.entry = uint40(
        (
            _amount * uint256(fromPosition.entry)
                + vars_.toAmount * uint256(toPosition.entry)
        ) / (_amount + vars_.toAmount)
    ); // unsafe cast ok
```

The issue with this calculation is that rounding is not in favor of the protocol, which enables for manipulation. A malicious user can simply repeatedly shift 1 wei from a very mature position to a recent one, decreasing the entry of the target position by 1 second repeatedly.

### Recommendation
`position.entry` should be rounded up in this calculation, please consider using Math.ceilDiv:

```diff
    toPosition.entry = uint40(
-        (
-            _amount * uint256(fromPosition.entry)
-                + vars_.toAmount * uint256(toPosition.entry)
-        ) / (_amount + vars_.toAmount)
+        Math.ceilDiv(
+            _amount * uint256(fromPosition.entry)
+                + vars_.toAmount * uint256(toPosition.entry),
+            _amount + vars_.toAmount
+        )
    ); // unsafe cast ok
```

### Fix review

Fixed by: [45fff8b3](https://github.com/beirao/Reliquary/commit/45fff8b362df8c29fedc1eaaafd106f15e5b9cf5)

## M-5 Linear average for entry can be gamed in case of non-linear curve functions

### Vulnerability details

A linear amount-weighted average is used to determine the new entry of a position during `deposit`/`shift`/`merge` operations. This enables a user to increase positions while keeping the same level for some non-linear configurations (in this case `LinearPlateauCurve`):


```
level   |       t   currentMaturity
        |       |        |
        |       v________v________
        |      /
        |     /
        |    /
        |   /
        |  /
        | /
        |/_______________________
        0       t    currentMaturity            time
```

We can see that in the case of a `curve` with the shape depicted above, adding an amount of `((currentMaturity-t)/currentMaturity)*oldAmount` will not modify the level of the position (the position will stay on the ceiling part of the curve).

As a result users can slightly game the non-linearity of the curve.

### Recommendation

To have optimal fairness when using non-linear curves, one should keep all entries separate to be able to recompute the correct balance of a position. An alternative, albeit not simple solution would be to recompute a new curve for the merged position.

### Fix review

Acknowledged

## L-1 Rewarder initialization Dos

### Vulnerability detail

A rewarder is initialized when added to a pool, this means that if the rewarder is not added in the same transaction as it is registered to the pool, the initialization can be front-run by anyone.

This only has the impact of making the `addPool` call revert which is low.

### Recommendation
Separate the logic of initialization which sets `reliquary`, and registering the rewarder for a pool in a separate function `registerPool`.

ParentRollingRewarder.sol:
```solidity
    function initialize(address _reliquary) external {
        if (reliquary != address(0)) {
            revert ParentRollingRewarder__ALREADY_INITIALIZED();
        }
        reliquary = _reliquary;
    }
```

ParentRollingRewarder.sol:
```solidity
    function registerPool(uint8 poolId) external {
        require(msg.sender == reliquary, "Not reliquary");
        if (poolId != type(uint8).max) {
            revert ParentRollingRewarder__ALREADY_INITIALIZED();
        }
        poolId = _poolId;
    }
```

### Fix review

Acknowledged

## L-2 deposit and shift/merge have a slightly different average formula

### Vulnerability detail
Functions which add some amount to an existing position must compute a weighted average to get the `entry` time of the new position.

The problem lies in the fact `shift` and `merge` have a slightly different formula than `deposit`. As discussed in M-1 the rounding used in `deposit` can be used to increase the amount of positions without increasing `entry`. The capacity to do so is greatly reduced by the formula used in `shift`:
[Reliquary::shift#L421-L426](https://github.com/beirao/Reliquary/blob/a3f686e4609f58bc5665c80f3f97eb9fe7c6d668/contracts/Reliquary.sol#L421-L426):
```
    toPosition.entry = uint40(
        (
            vars_.fromAmount * uint256(fromPosition.entry)
                + vars_.toAmount * uint256(toPosition.entry)
        ) / (vars_.fromAmount + vars_.toAmount)
    ); // unsafe cast ok
```

> Please note that the formula used in shift also rounds the entry down, which is not favorable to the protocol

### Recommendation
Use the same function to compute the weighted average for `entry` (preferably the one currently used in shift).

### Fix review

Fixed by: [45fff8b3](https://github.com/beirao/Reliquary/commit/45fff8b362df8c29fedc1eaaafd106f15e5b9cf5)


## L-3 When a pool is updated and totalLpSupply == 0 the rewards are lost for the pool

### Vulnerability detail

When totalLpSupply == 0, the logic of distributing rewards is skipped, to avoid a division by zero:
[ReliquaryLogic.sol#L136-L141](https://github.com/beirao/Reliquary/blob/a3f686e4609f58bc5665c80f3f97eb9fe7c6d668/contracts/libraries/ReliquaryLogic.sol#L136-L141)
```solidity
    if (lpSupply_ != 0) {
        uint256 reward_ = (secondsSinceReward_ * _emissionRate * uint256(pool.allocPoint))
            / _totalAllocPoint;
        accRewardPerShare_ += Math.mulDiv(reward_, ACC_REWARD_PRECISION, lpSupply_);
        pool.accRewardPerShare = accRewardPerShare_;
    }

    pool.lastRewardTime = uint40(timestamp_);
```

Unless the protocol team supplies some amount of tokens when creating a pool, some amount of rewards can be lost if updating the pool when it is empty.

> A variant of this is also present in the `RollingRewarder`, where the funded can be lost if the rewarder was already funded, which seems less likely than in `ReliquaryLogic`.
> [RollingRewarder.sol#L276-L281](https://github.com/beirao/Reliquary/blob/a3f686e4609f58bc5665c80f3f97eb9fe7c6d668/contracts/rewarders/RollingRewarder.sol#L276-L281)

### Recommendation

Since the `emissionRate` is shared accross pools, one can first remove `pool.allocPoint` from `_totalAllocPoint` when pools are empty before actually distribute the rewards, which would share the pending rewards among pools which are not empty. 

### Fix review

Fixed by: [f262a1eb](https://github.com/beirao/Reliquary/commit/f262a1ebe9c45d7514028604152a702f8f6470b5)


## Informational/Gas
### INFO-1 Change condition to require for readability
The following formula to check for an overflow would be more readable if expressed as an explicit require:
https://github.com/beirao/Reliquary/blob/a3f686e4609f58bc5665c80f3f97eb9fe7c6d668/contracts/Reliquary.sol#L122

### INFO-2 Reentrancy available in burn()
`Reliquary::burn()` lacks a `nonReentrant` modifier, the reentrancy can be used in `_safeMint()` during a call to `split()` to create an orphan position (actual position without an nft).

### INFO-3 Reliquary::burn() doesn't clean positionForId mapping
As a result `pendingReward()` view function can return non-zero values for a burnt relic

### GAS-1 Better avoid returning the whole PoolInfo struct when using a specific parameter
[RollingRewarder.sol#L268](https://github.com/beirao/Reliquary/blob/a3f686e4609f58bc5665c80f3f97eb9fe7c6d668/contracts/rewarders/RollingRewarder.sol#L268)

[RollingRewarder.sol#L289](https://github.com/beirao/Reliquary/blob/a3f686e4609f58bc5665c80f3f97eb9fe7c6d668/contracts/rewarders/RollingRewarder.sol#L289)

[RollingRewarder.sol#L304](https://github.com/beirao/Reliquary/blob/a3f686e4609f58bc5665c80f3f97eb9fe7c6d668/contracts/rewarders/RollingRewarder.sol#L304)

Some considerable amount of gas can be saved by implementing the specific accessors:
`getTotalLpSupplied` and `getPoolCurve`, instead of loading the whole `PoolInfo` struct from storage into memory as done currently.

### Fix review
Informational and gas issues (excepted INFO-1 which is acknowledged), have been fixed by: [5477f2a9](https://github.com/beirao/Reliquary/commit/5477f2a9cb348bed675dff9aad8216d3f157a0c6) and [158ee9ef](https://github.com/beirao/Reliquary/commit/158ee9efed0902ee963be9b2729e5d303920cf38)