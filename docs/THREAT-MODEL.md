# Threat model

Who could take or block money, what the code does about it, and what is left over.

| Threat | What the code does | Remaining risk (honest) |
| --- | --- | --- |
| **Maintainer takes sponsor money** | No owner function moves ETH. The owner can only propose, cancel and freeze splits, and transfer ownership. Proven by `test_ownerCannotTouchFunds` and by invariants that fuzz owner actions. | None for funds already credited. |
| **Maintainer rewrites the split to 100% for themselves** | Change must be public for `splitChangeDelay` (>= 1 hour, deployed with 2 days) and applies **only to future deposits**. Credited balances never change. `freezeSplit()` removes the power. | Future payments can be redirected after the delay. Sponsors must watch the pending-change warning or rely on a frozen split. |
| **Maintainer key stolen** | Two-step ownership transfer; same limits as above. | Attacker gets the same limited power: propose a split and wait the delay. Watchers can react and sponsors can stop paying. |
| **Reentrancy on withdraw** | Balance zeroed before the external call, plus `ReentrancyGuard`. Test uses a real attacker contract. | None known. |
| **One recipient that reverts** | Pull model. Their failure only affects their own withdrawal, and `withdrawTo` lets them redirect. | Their funds stay claimable but they need a working address. |
| **Return-data bomb** | Return data is ignored. Test with a 200 KB return. | None known. |
| **Forced ETH (`selfdestruct`)** | Accounting uses tracked totals, not `balance`. `sync()` splits stray ETH publicly. | Stray ETH is distributed by the active split, which is the only reasonable rule. |
| **Rounding theft** | Dust is at most `n-1` wei per deposit, goes to the last listed share, and is bounded by fuzz test. | The last recipient gains up to `n-1` wei per deposit. Wei-sized, public, deliberate. |
| **Gas griefing with many recipients** | Max 30 recipients, credit loop makes no external calls. | A deposit to a 30-recipient split costs more gas. |
| **Strangers withdrawing for others** | `withdraw()` only pays `msg.sender`. | None. |
| **Sponsor sends with 2300-gas `transfer`** | `receive()` writes storage, so `transfer` and `send` will fail. | Sponsors must use `call` or a normal wallet. This is the standard modern pattern. |
| **Recipient loses their key** | `withdrawTo` lets them pre-route payouts. | A lost key means that balance is unreachable. No admin recovery exists, by design. |
| **Contract bugs** | 100% line coverage, fuzz and invariant tests, no dependencies except OpenZeppelin `Ownable2Step` and `ReentrancyGuard`. | Not independently audited. Do not put large sums behind it without an audit. |
| **Front-end compromise** | The page only reads the contract and builds transactions the wallet shows. Everything works with `cast` or Etherscan. | A hosted copy of the page can be replaced. The contract is the source of truth. |
| **ERC-20 and NFTs sent to the contract** | Not supported. They are not counted and cannot be recovered. | Sponsors must send ETH. |
