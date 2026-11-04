# Architecture

One contract, no proxy, no upgrade path, no off-chain service.

## State

| Variable | Meaning |
| --- | --- |
| `_shares[]` | Active split: `(account, bps, label)` |
| `_pending[]`, `pendingActivatesAt` | A proposed split and when it may take effect |
| `owed[account]` | What the account can withdraw now |
| `totalEarned[account]` | Lifetime credits (for display) |
| `totalCredited`, `totalWithdrawn` | Global counters. `outstanding = credited - withdrawn` |
| `splitVersion`, `splitFrozen` | Governance bookkeeping |

## Flows

**Deposit** (`receive` / `fund`): emit `Funded`, then `_credit(amount)` loops through the active split. Each
share except the last gets `amount * bps / 10_000`. The last gets `amount - distributed`. `totalCredited += amount`.
No external call is made.

**Withdraw**: `owed[caller] = 0`, `totalWithdrawn += amount`, then a single `call` to the destination. If the
call fails, everything reverts and the balance is restored.

**Change the split**: `proposeSplit` (owner) stores the new split and sets the activation time. After the delay,
anyone calls `activateSplit`, which swaps it in and bumps `splitVersion`. `cancelSplitProposal` and
`freezeSplit` are owner-only. None of them touch `owed` or ETH.

**Stray ETH**: `sync()` credits `balance - outstanding` through the active split.

## Invariants (all fuzzed in `test/Invariant.t.sol`)

1. `balance >= outstanding` (always solvent)
2. `balance == funded + forced - withdrawn`
3. `totalCredited == funded + synced`
4. `sum(owed over actors) == outstanding`
5. For every account: `withdrawn <= earned`, and `earned == owed + withdrawn`
6. The active split always sums to 10,000 bps
7. `unaccounted == forced - synced`

## Why these choices

- Credit-on-deposit makes "new split affects future money only" structural, not a rule to remember.
- Pull payments mean the deposit path cannot be blocked by anyone.
- No upgradeability: nobody, including the deployer, can change the rules after deployment.
