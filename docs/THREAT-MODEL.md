# Threat model

Who could take or block money, what the code does about it, and what is left over.

| Threat | What the code does | Remaining risk (honest) |
| --- | --- | --- |
| **Maintainer takes sponsor money** | No owner function moves ETH. The owner can only propose, cancel and freeze splits, and transfer ownership. Proven by `test_ownerCannotTouchFunds` and by invariants that fuzz owner actions. | None for funds already credited. |
| **Maintainer rewrites the split to 100% for themselves** | Change must be public for `splitChangeDelay` (>= 1 hour, deployed with 2 days) and applies **only to future deposits**. Credited balances never change. `freezeSplit()` removes the power. | Future payments can be redirected after the delay. Sponsors must watch the pending-change warning or rely on a frozen split. |
| **Maintainer key stolen** | Two-step ownership transfer; `renounceOwnership` is disabled so a pending proposal can never become uncancellable. | Attacker gets the maintainer's power: propose a split and wait the delay, and also `freezeSplit()` (irreversible), so a bad split could be made permanent. Watchers can react and sponsors can stop paying. |
| **Sponsor payment in flight while a split activates** | `fundWithVersion(expectedVersion)` reverts if the split changed; the web page uses it. | A plain transfer to the address (or `fund()`) is split by whatever is active when it lands. |
| **Stray ETH split by a later split** | `activateSplit()` first credits stray ETH under the OLD split. Test: `test_strayEth_isSplitByTheSplitInForceWhenItArrived`. | None known. |
| **Recipient that can never collect** (dead key, or a contract that cannot receive ETH or call `withdrawTo`) | The contract cannot judge addresses. | Credits to such an address are locked forever. Sponsors can read the list first. |
| **Labels are unverified text** | Labels are shown as typed (React escapes them). | The maintainer could label their own address "OpenZeppelin". Verify addresses, not labels. |
| **Stale pending proposal** | Visible in the UI; re-proposing resets the delay. | A proposal never expires on its own. Anyone can activate it after the delay unless the maintainer cancels. |
| **Reentrancy on withdraw** | Balance zeroed before the external call, plus `ReentrancyGuard`. Test uses a real attacker contract. | None known. |
| **One recipient that reverts** | Pull model. Their failure only affects their own withdrawal, and `withdrawTo` lets them redirect. | Their funds stay claimable but they need a working address. |
| **Return-data bomb** | Return data is ignored. Test with a 200 KB return. | None known. |
| **Forced ETH (`selfdestruct`)** | Accounting uses tracked totals, not `balance`. `sync()` splits stray ETH publicly. | Stray ETH is split by the split active when `sync()` is called, or by the old split if a change activates first. |
| **Rounding theft** | Dust is at most `n-1` wei per deposit, goes to the last listed share, and is bounded by fuzz test. | For a deposit so small that every other share rounds to zero (e.g. 1 wei), the whole deposit goes to the last listed share. Many tiny deposits cost more gas than they move, but the effect is real and the maintainer chooses who is last. |
| **Gas griefing with many recipients** | Max 30 recipients, credit loop makes no external calls. | Measured by the reviewer: about 1.5M gas for a first deposit and about 0.5M for later ones at 30 recipients. Senders that forward limited gas (some multisigs, forwarders, `transfer`'s 2300) will fail. Use a normal wallet or `call` with enough gas. |
| **Strangers withdrawing for others** | `withdraw()` only pays `msg.sender`. | None. |
| **Sponsor sends with 2300-gas `transfer`** | `receive()` writes storage, so `transfer` and `send` will fail. | Sponsors must use `call` or a normal wallet. This is the standard modern pattern. |
| **Recipient loses their key** | `withdrawTo` lets them pre-route payouts. | A lost key means that balance is unreachable. No admin recovery exists, by design. |
| **Contract bugs** | 100% line coverage, fuzz and invariant tests, no dependencies except OpenZeppelin `Ownable2Step` and `ReentrancyGuard`. | Reviewed by an independent AI reviewer (its findings are fixed above), but not audited by a human firm. Do not put large sums behind it without an audit. |
| **Front-end compromise** | The page only reads the contract and builds transactions the wallet shows. Everything works with `cast` or Etherscan. | A hosted copy of the page can be replaced. The contract is the source of truth. |
| **ERC-20 and NFTs sent to the contract** | Not supported. They are not counted and cannot be recovered. | Sponsors must send ETH. |
