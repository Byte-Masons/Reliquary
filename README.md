# Reliquary
#### Designed and Written by Justin Bebis with help from Zokunei, Goober, and the rest of the Byte Masons crew
---
Reliquary is a modified MasterchefV2 contract that is designed to
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
that initial depositors will set the curve and usually receive the maximum amount possible at any given time.
There are complex ways to combat this, but we've settled on a whitelisting system to pair with our Reaper.Farm
vaults, which would only allow the strategy to enter at first, setting the curve over a period of a couple weeks
before we allow everyone else to enter. Because each curve we use flattens out, this will allow the pool to behave
more or less as expected in the short to medium term.

Also something to note is the total average recorded in the pool is moved up and down the curve based on deposits
and withdrawals agnostic to the user performing the deposit or withdrawal. While users are individually penalized for
their movement in and out, the pool as a whole seeks to achieve 'zero sum' behavior regardless of the context of each
interaction.
