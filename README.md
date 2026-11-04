# Pay It Upstream

**Persona: Meera, maintainer of `tiny-lib`**, a small open-source library with two regular contributors
and two big dependencies. Sponsors keep paying her personal wallet. She then pays Asha and Ravi by hand,
late, and never pays the libraries underneath. She wants **one address sponsors can pay, a split anyone
can read, and a way for every contributor and upstream project to collect what they are owed**, without
ever being the person who holds the money.

Pay It Upstream is one Solidity contract (`UpstreamSplitter`) plus a small web page. Built for Devcon 8
Build Battle 2, "Pay It Upstream".

> **The test from the brief:** the maintainer never touches the money, and nobody, including the
> maintainer, can quietly keep what belongs to someone else.
> Both halves are enforced by code and proven by tests. See [Brief to evidence](#brief-to-evidence).

## How it works, in plain words

1. **Sponsors pay one address**: the contract. Plain ETH transfer, or `fund()`.
2. **The split is public**: for example 40% Meera, 20% Asha, 10% Ravi, 20% viem, 10% OpenZeppelin. It lives in
   the contract and the web page shows it as sentences and bars.
3. **Every payment is divided on arrival**: each person's balance goes up. Nothing is sent to anyone yet.
4. **Everyone collects their own share**: `withdraw()` pays the caller only. Nobody else can trigger or block it.

```
Sponsor ──ETH──▶ UpstreamSplitter ──credit──▶ owed[Meera] owed[Asha] owed[Ravi] owed[viem] owed[OZ]
                      ▲                                   │ each person calls withdraw()
                      │ maintainer can only                ▼
                      └ propose a new split          their own wallet
                        (public delay, future money only)
```

## Brief to evidence

| What the brief asks | Where it is enforced | Where it is proven |
| --- | --- | --- |
| One address sponsors can pay | `receive()` and `fund()` in `src/UpstreamSplitter.sol` | `test_receive_creditsEveryShare`, `test_fund_function_sameAsReceive` |
| A split anyone can read | `getSplit()`, `getPendingSplit()`, `preview()`, labels stored on-chain; web page reads them directly | `test_constructor_setsState`, `test_preview_matchesRealCredit`; web `Where every payment goes` |
| Every contributor and upstream project can collect | `withdraw()` / `withdrawTo()` | `test_withdraw_paysCallerOnly`, `test_everyoneWithdraws_contractEndsAtZero`, `testFuzz_depositsThenAllWithdraw` |
| **Maintainer never touches the money** | The `owner` role can only call `proposeSplit`, `cancelSplitProposal`, `freezeSplit` and ownership transfer. No function lets it move ETH. | `test_ownerCannotTouchFunds`, invariants (owner actions are part of the random walk) |
| **Nobody can quietly keep what belongs to someone else** | Balances are credited at deposit time and zeroed only by their owner. A split change applies to future deposits only. | `test_propose_waitsForDelay_thenAnyoneActivates`, `invariant_noOneTookMoreThanTheyEarned`, `testFuzz_strangerCannotTouchOthers` |
| Pull, don't push (one bad address cannot block everyone) | No external call happens while money comes in. | `test_withdraw_toRevertingContract_failsAndKeepsBalance`, `test_withdraw_returnBombDoesNotBlock` |
| Integer math: decide where every wei goes | Every share but the last is rounded down; the **last listed share gets the remainder** (at most `n-1` wei). | `test_dust_goesToLastShare_andNothingIsLost`, `testFuzz_conservation`, `testFuzz_dustIsBounded` |
| Guard the exit | Balance zeroed before the call, plus `ReentrancyGuard` | `test_withdraw_reentrancyIsBlocked` |
| No admin sweep | There is no such function. Forced-in ETH is split by the public `sync()`, not swept. | `test_forcedEth_doesNotCorruptAccounting_andCanBeSynced`; `forge inspect UpstreamSplitter methods` |
| Readable by non-developers | Web page: percentages, ETH amounts, "You are owed…", plain error messages | `web/src/lib.test.ts` |
| Own funds-handling logic (not a Drips wrapper) | All logic is in this repo; OpenZeppelin is used only for `Ownable2Step` and `ReentrancyGuard` | `src/UpstreamSplitter.sol` |
| Deploy to Sepolia | `script/Deploy.s.sol` | See [Deployment](#deployment) |

## Design decisions (and why)

- **Credit on arrival, not lazy accounting.** Deposits loop over at most 30 recipients and only write
  storage. That is cheap, simple to audit, and makes "a new split affects only future money" true by
  construction. The cost is gas that grows with recipient count, hence the cap of 30.
- **The last share takes the rounding remainder.** Dust is at most `n-1` wei per deposit, bounded by a fuzz
  test. The UI marks the last person "gets rounding leftovers" so nothing is hidden. Put your most
  patient recipient last.
- **The split can change, but publicly and for the future only.** Meera can propose a new split. It is
  visible on-chain and in the UI for `splitChangeDelay` (1 hour to 30 days). Then anyone can activate it.
  Already-credited balances are never touched. She can also `freezeSplit()` to make the current split permanent.
- **Accounting never trusts `address(this).balance`.** ETH forced in by `selfdestruct` cannot corrupt balances.
  Anyone can call `sync()` to split it by the active rules.
- **ETH only.** ERC-20 support is deliberately out of scope so the core stays small enough to verify completely.

## Run it

```bash
# contracts (Foundry)
forge build
forge test                     # unit + fuzz (1000 runs each) + invariants
forge coverage --no-match-coverage "test|script" --no-match-test invariant

# web (Vite + React + wagmi + viem)
cd web && npm install
npm test && npm run build
cp .env.example .env           # set VITE_SPLITTER_ADDRESS, then:
npm run dev
```

## Tests

| Layer | What | Count |
| --- | --- | --- |
| Unit | Every revert, every edge case: dust, 1 wei, 0 wei, 30 recipients, forced ETH, reentrancy, reverting and return-bomb recipients, governance, ownership | 40 |
| Fuzz | Random splits and amounts: credited == deposited, dust bound, deposits then full withdrawal ends at zero, strangers cannot touch balances | 5 |
| Invariant | A random walk of sponsors, recipients, strangers **and the owner** (16,384 calls per run): solvency, balance equals flows, credited equals deposited plus synced, sum of balances equals outstanding, nobody withdraws more than earned, split always sums to 10,000 | 7 |
| Web | Percent and ETH formatting, deposit preview that mirrors the contract's rounding, input parsing, plain-language errors | 9 |

Coverage of `src/UpstreamSplitter.sol`: **100% lines (119/119), 100% functions (20/20)**, 99.3% statements,
96.2% branches. The one branch the tool reports as unhit is the constructor name-length check; its test
exists and passes, which looks like a coverage-tool quirk with reverting constructors, not a missing test.

## Deployment

Local end-to-end run done with Anvil: deploy via `script/Deploy.s.sol`, sponsor 1 ETH, balances read back
(0.4 / 0.2 / 0.1 / 0.2 / 0.1), one recipient withdrew, a stranger's `withdraw()` reverted with
`NothingToWithdraw`, and an invalid split reverted with `BpsDoNotSumTo10000`.

**Sepolia:** _not deployed yet. This section is filled with the real contract address, a real sponsor
transaction and a real withdrawal transaction immediately after deployment._

To deploy:

```bash
cp .env.example .env   # fill recipients, RPC and Etherscan key
source .env
forge script script/Deploy.s.sol --rpc-url sepolia --account <keystore-name> --broadcast --verify
```

## Honest limits

See [docs/THREAT-MODEL.md](docs/THREAT-MODEL.md). In short: the maintainer can still redirect **future**
payments after the public delay (sponsors can see this coming, and `freezeSplit()` removes the power);
a recipient who loses their key loses their balance (they can pre-set a safe address with `withdrawTo`);
ETH only; and the contract has not been independently audited.

## Layout

```
src/UpstreamSplitter.sol     the whole funds-handling contract
script/Deploy.s.sol          env-driven deploy
test/                        unit, fuzz and invariant tests, plus attacker contracts in test/helpers
web/src/                     abi.ts, lib.ts (pure helpers + tests), App.tsx (reads straight from the contract)
docs/                        ARCHITECTURE.md, THREAT-MODEL.md
```

Prior art: [Drips](https://www.drips.network) splits open-source funding to maintainers and dependencies.
This repo shares the goal but contains its own funds-handling logic.
