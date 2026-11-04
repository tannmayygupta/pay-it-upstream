# Walkthrough video script (about 3 minutes)

The submission needs a short video. Record your screen (OBS, Loom or the built-in Windows recorder with
`Win + G`) with a terminal and the repo open. Speak the lines in quotes; the bullets are what is on screen.

**0:00 The problem (20 s)**
- Show the README top.
- "Meera maintains a small library. Sponsors pay her personal wallet, she pays contributors by hand, and the
  libraries underneath get nothing. We built one address, a public split, and withdrawals that nobody can block."

**0:20 The contract (40 s)**
- Open `src/UpstreamSplitter.sol`, scroll the header comment and the function list.
- "Money in only writes balances. Each person calls withdraw for their own share. The maintainer role can
  only propose a new split, publicly, after a delay, for future money. There is no function that moves
  anyone else's ETH."

**1:00 Tests (40 s)**
- In the terminal run `forge test`, then show 54 passing and the coverage line.
- "Invariants run a random walk that includes the maintainer's powers: the contract is always solvent,
  credited equals deposited to the wei, and nobody can withdraw more than they earned."

**1:40 End-to-end demo (50 s)**
- Run `bash scripts/demo-local.sh` and let it scroll.
- Point at: the split, "contract holds 1 ETH = total owed", the stranger's `NothingToWithdraw`, the invalid
  split rejection, the contract ending at 0, and 7 wei of dust fully accounted for.

**2:30 Web page and honesty (30 s)**
- Show the page (`cd web && npm run dev`): split as bars and sentences, "You are owed".
- "Limits are in the threat model: the maintainer can redirect future payments after the public delay, it is
  ETH only, and it has had an AI review but not a human audit."
