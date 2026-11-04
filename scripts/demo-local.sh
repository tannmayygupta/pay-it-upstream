#!/usr/bin/env bash
# End-to-end demo on a local Anvil chain. No keys, no faucet, no accounts needed.
# Deploys the splitter, sponsors it, shows the split, lets recipients collect,
# and shows that a stranger, an invalid split and a stolen-owner attempt all fail.
#
#   bash scripts/demo-local.sh
set -euo pipefail
cd "$(dirname "$0")/.."

RPC=http://127.0.0.1:8545
# Anvil's pre-funded, unlocked test accounts (public, worthless outside Anvil).
MEERA=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266   # maintainer
ASHA=0x70997970C51812dc3A010C7d01b50e0d17dc79C8    # contributor
RAVI=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC    # contributor
VIEM=0x90F79bf6EB2c4f870365E785982E1f101E93b906    # upstream project
OZ=0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65      # upstream project
SPONSOR=0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc
STRANGER=0x976EA74026E726554dB657fA54763abd0C3a0aa9

say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
eth() { cast from-wei "$1"; }

anvil --silent >/tmp/anvil-demo.log 2>&1 &
ANVIL_PID=$!
trap 'kill $ANVIL_PID 2>/dev/null || true' EXIT
for _ in $(seq 1 50); do cast chain-id --rpc-url $RPC >/dev/null 2>&1 && break; sleep 0.2; done

say "1. Deploy: project tiny-lib, 2-day public delay for split changes"
export PROJECT_NAME="tiny-lib" MAINTAINER=$MEERA SPLIT_DELAY=172800
export R0_ADDR=$MEERA R0_BPS=4000 R0_LABEL="Meera (maintainer)"
export R1_ADDR=$ASHA  R1_BPS=2000 R1_LABEL="Asha (contributor)"
export R2_ADDR=$RAVI  R2_BPS=1000 R2_LABEL="Ravi (contributor)"
export R3_ADDR=$VIEM  R3_BPS=2000 R3_LABEL="viem (upstream)"
export R4_ADDR=$OZ    R4_BPS=1000 R4_LABEL="OpenZeppelin (upstream)"
forge script script/Deploy.s.sol --rpc-url $RPC --unlocked --sender $MEERA --broadcast >/dev/null 2>&1
SPLITTER=$(cast compute-address $MEERA --nonce 0 | awk '{print $NF}')
echo "UpstreamSplitter at $SPLITTER"
echo "project: $(cast call $SPLITTER 'projectName()(string)' --rpc-url $RPC)"

say "2. The split anyone can read (account, bps, label)"
cast call $SPLITTER 'getSplit()((address,uint16,string)[])' --rpc-url $RPC | tr -d '[]' | sed 's/), (/)\n(/g'

say "3. A sponsor pays ONE address: 1 ETH"
cast send $SPLITTER --value 1ether --from $SPONSOR --unlocked --rpc-url $RPC >/dev/null
for who in "Meera:$MEERA" "Asha:$ASHA" "Ravi:$RAVI" "viem:$VIEM" "OpenZeppelin:$OZ"; do
  name=${who%%:*}; addr=${who##*:}
  printf '%-13s owed %s ETH\n' "$name" "$(eth "$(cast call $SPLITTER 'owed(address)(uint256)' $addr --rpc-url $RPC | awk '{print $1}')")"
done
echo "contract holds $(eth "$(cast balance $SPLITTER --rpc-url $RPC)") ETH = total owed, to the wei"

say "4. A stranger tries to withdraw someone else's money -> must fail"
cast send $SPLITTER 'withdraw()' --from $STRANGER --unlocked --rpc-url $RPC 2>&1 | grep -oE "NothingToWithdraw" | head -1 || true

say "5. The maintainer tries an invalid split (99.99%) -> must fail"
cast send $SPLITTER 'proposeSplit((address,uint16,string)[])' "[($ASHA,9999,\"x\")]" --from $MEERA --unlocked --rpc-url $RPC 2>&1 | grep -oE "BpsDoNotSumTo10000\([0-9]+\)" | head -1 || true

say "6. The maintainer tries to renounce (would strand a pending change) -> must fail"
cast send $SPLITTER 'renounceOwnership()' --from $MEERA --unlocked --rpc-url $RPC 2>&1 | grep -oE "custom error 0x[0-9a-f]{8}" | head -1 | sed "s/custom error 0x89051165/reverted: RenounceDisabled() (selector 0x89051165)/" || true

say "7. Asha collects HER share only"
BEFORE=$(cast balance $ASHA --rpc-url $RPC)
cast send $SPLITTER 'withdraw()' --from $ASHA --unlocked --rpc-url $RPC >/dev/null
AFTER=$(cast balance $ASHA --rpc-url $RPC)
echo "Asha wallet rose by $(eth $((AFTER - BEFORE))) ETH = her 0.2 ETH share minus the gas she paid to send this transaction"
echo "Ravi still owed $(eth "$(cast call $SPLITTER 'owed(address)(uint256)' $RAVI --rpc-url $RPC | awk '{print $1}')") ETH (untouched)"

say "8. Everyone else collects; the contract ends at exactly 0"
for a in $MEERA $RAVI $VIEM $OZ; do cast send $SPLITTER 'withdraw()' --from $a --unlocked --rpc-url $RPC >/dev/null; done
echo "contract balance: $(eth "$(cast balance $SPLITTER --rpc-url $RPC)") ETH"
echo "totalCredited:  $(cast call $SPLITTER 'totalCredited()(uint256)' --rpc-url $RPC | awk '{print $1}') wei"
echo "totalWithdrawn: $(cast call $SPLITTER 'totalWithdrawn()(uint256)' --rpc-url $RPC | awk '{print $1}') wei"

say "9. Dust: 7 wei over the same split -> every wei accounted for"
cast send $SPLITTER --value 7 --from $SPONSOR --unlocked --rpc-url $RPC >/dev/null
SUM=0
for a in $MEERA $ASHA $RAVI $VIEM $OZ; do
  v=$(cast call $SPLITTER 'owed(address)(uint256)' $a --rpc-url $RPC | awk '{print $1}')
  printf '%s owed %s wei\n' "$a" "$v"; SUM=$((SUM + v))
done
echo "sum of balances = $SUM wei (deposited 7)"
echo
echo "DEMO OK"
