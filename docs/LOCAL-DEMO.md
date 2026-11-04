# Local end-to-end demo (real captured output)

Produced by `bash scripts/demo-local.sh` on a local Anvil chain on 2026-11-04. It needs no keys, faucet or accounts, so anyone can reproduce it. Each step either shows the money moving as promised or shows an attack being rejected.

```

== 1. Deploy: project tiny-lib, 2-day public delay for split changes
UpstreamSplitter at 0x5FbDB2315678afecb367f032d93F642f64180aa3
project: "tiny-lib"

== 2. The split anyone can read (account, bps, label)
(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, 4000, "Meera (maintainer)")
(0x70997970C51812dc3A010C7d01b50e0d17dc79C8, 2000, "Asha (contributor)")
(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC, 1000, "Ravi (contributor)")
(0x90F79bf6EB2c4f870365E785982E1f101E93b906, 2000, "viem (upstream)")
(0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65, 1000, "OpenZeppelin (upstream)")

== 3. A sponsor pays ONE address: 1 ETH
Meera         owed 0.400000000000000000 ETH
Asha          owed 0.200000000000000000 ETH
Ravi          owed 0.100000000000000000 ETH
viem          owed 0.200000000000000000 ETH
OpenZeppelin  owed 0.100000000000000000 ETH
contract holds 1.000000000000000000 ETH = total owed, to the wei

== 4. A stranger tries to withdraw someone else's money -> must fail
NothingToWithdraw

== 5. The maintainer tries an invalid split (99.99%) -> must fail
BpsDoNotSumTo10000(9999)

== 6. The maintainer tries to renounce (would strand a pending change) -> must fail
reverted: RenounceDisabled() (selector 0x89051165)

== 7. Asha collects HER share only
Asha wallet rose by 0.199956814302834046 ETH = her 0.2 ETH share minus the gas she paid to send this transaction
Ravi still owed 0.100000000000000000 ETH (untouched)

== 8. Everyone else collects; the contract ends at exactly 0
contract balance: 0.000000000000000000 ETH
totalCredited:  1000000000000000000 wei
totalWithdrawn: 1000000000000000000 wei

== 9. Dust: 7 wei over the same split -> every wei accounted for
0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 owed 2 wei
0x70997970C51812dc3A010C7d01b50e0d17dc79C8 owed 1 wei
0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC owed 0 wei
0x90F79bf6EB2c4f870365E785982E1f101E93b906 owed 1 wei
0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65 owed 3 wei
sum of balances = 7 wei (deposited 7)

DEMO OK
```
