import { useEffect, useMemo, useState } from "react";
import { isAddress } from "viem";
import {
  useAccount,
  useConnect,
  useDisconnect,
  useReadContract,
  useReadContracts,
  useSwitchChain,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import { splitterAbi } from "./abi";
import { chain, explorer, splitterAddress } from "./config";
import {
  bpsToPercent,
  describeSplit,
  formatEth,
  friendlyError,
  parseEthInput,
  previewDeposit,
  shortAddr,
  timeLeft,
  type Share,
} from "./lib";

const POLL = 8_000;

/** Wrap a contract write with pending / confirmed / error state a person can read. */
function useTx() {
  const { writeContractAsync, data: hash, isPending, reset } = useWriteContract();
  const receipt = useWaitForTransactionReceipt({ hash });
  const [error, setError] = useState<string | null>(null);
  async function send(args: Record<string, unknown>) {
    setError(null);
    try {
      await writeContractAsync(args as never);
    } catch (e) {
      setError(friendlyError(e));
    }
  }
  return {
    send,
    error,
    hash,
    waiting: isPending || (!!hash && receipt.isLoading),
    done: receipt.isSuccess,
    reset,
  };
}

function TxStatus({ tx, doneText }: { tx: ReturnType<typeof useTx>; doneText: string }) {
  if (tx.error) return <p className="err" role="alert">{tx.error}</p>;
  if (tx.waiting) return <p className="note">Waiting for the network to confirm…</p>;
  if (tx.done)
    return (
      <p className="ok" role="status">
        {doneText}{" "}
        {explorer && tx.hash && (
          <a href={`${explorer}/tx/${tx.hash}`} target="_blank" rel="noreferrer">
            view transaction
          </a>
        )}
      </p>
    );
  return null;
}

export function App() {
  if (!splitterAddress) {
    return (
      <main>
        <h1>Pay It Upstream</h1>
        <p className="err" role="alert">
          No contract address is configured. Set <code>VITE_SPLITTER_ADDRESS</code> in <code>web/.env</code> and rebuild.
        </p>
      </main>
    );
  }
  return <Dashboard address={splitterAddress} />;
}

function Dashboard({ address }: { address: `0x${string}` }) {
  const base = { address, abi: splitterAbi, chainId: chain.id } as const;
  const { data, refetch } = useReadContracts({
    contracts: [
      { ...base, functionName: "projectName" },
      { ...base, functionName: "getSplit" },
      { ...base, functionName: "getPendingSplit" },
      { ...base, functionName: "outstanding" },
      { ...base, functionName: "unaccounted" },
      { ...base, functionName: "splitFrozen" },
      { ...base, functionName: "splitVersion" },
      { ...base, functionName: "owner" },
      { ...base, functionName: "totalCredited" },
      { ...base, functionName: "totalWithdrawn" },
      { ...base, functionName: "splitChangeDelay" },
    ],
    query: { refetchInterval: POLL },
  });

  const r = (i: number) => (data?.[i]?.status === "success" ? data[i]!.result : undefined);
  const name = r(0) as string | undefined;
  const split = ((r(1) as readonly Share[] | undefined) ?? []).map((s) => ({ ...s }));
  const pending = r(2) as readonly [readonly Share[], bigint] | undefined;
  const outstanding = (r(3) as bigint | undefined) ?? 0n;
  const unaccounted = (r(4) as bigint | undefined) ?? 0n;
  const frozen = r(5) as boolean | undefined;
  const version = r(6) as bigint | undefined;
  const owner = r(7) as string | undefined;
  const credited = (r(8) as bigint | undefined) ?? 0n;
  const withdrawn = (r(9) as bigint | undefined) ?? 0n;
  const delay = r(10) as bigint | undefined;

  return (
    <main>
      <header>
        <p className="eyebrow">Pay It Upstream</p>
        <h1>{name || "Loading project…"}</h1>
        <p className="lead">
          Sponsors pay <strong>one address</strong>. The split below is public and enforced by code. Everyone collects their own
          share. The maintainer never touches the money.
        </p>
        <Wallet />
      </header>

      <section aria-labelledby="split-h">
        <h2 id="split-h">Where every payment goes</h2>
        {split.length === 0 ? (
          <p className="note">Reading the split from the blockchain…</p>
        ) : (
          <>
            <ul className="split">
              {split.map((s, i) => (
                <li key={s.account}>
                  <div className="bar" style={{ width: `${Number(s.bps) / 100}%` }} aria-hidden="true" />
                  <span className="who">
                    {s.label || shortAddr(s.account)} <small className="addr">{shortAddr(s.account)}</small>
                    {owner && s.account.toLowerCase() === owner.toLowerCase() && <em className="tag">maintainer</em>}
                    {i === split.length - 1 && <em className="tag" title="Rounding leftovers (a few wei at most) go to the last person on the list">gets rounding leftovers</em>}
                  </span>
                  <span className="pct">{bpsToPercent(Number(s.bps))}</span>
                </li>
              ))}
            </ul>
            <p className="note">
              In words: {describeSplit(split).join("; ")}. Split version {String(version ?? 1n)}.{" "}
              {frozen ? "🔒 This split is locked forever." : `The maintainer can propose a change, but it must be public for ${timeLeft(Number(delay ?? 0n))} first and only affects future payments.`}
            </p>
          </>
        )}
      </section>

      <Sponsor address={address} split={split} version={version ?? 1n} onDone={refetch} />
      <MyMoney address={address} onDone={refetch} />
      <Lookup address={address} />
      <Pending address={address} pending={pending} frozen={!!frozen} onDone={refetch} />

      {unaccounted > 0n && <Stray address={address} amount={unaccounted} onDone={refetch} />}

      <section aria-labelledby="proof-h">
        <h2 id="proof-h">The proof is on-chain</h2>
        <dl className="stats">
          <div><dt>Total paid in</dt><dd>{formatEth(credited)}</dd></div>
          <div><dt>Total collected so far</dt><dd>{formatEth(withdrawn)}</dd></div>
          <div><dt>Waiting to be collected</dt><dd>{formatEth(outstanding)}</dd></div>
        </dl>
        <p className="note">
          Paid in = collected + waiting, always, to the wei. Contract:{" "}
          {explorer ? <a href={`${explorer}/address/${address}`} target="_blank" rel="noreferrer">{address}</a> : <code>{address}</code>}
        </p>
      </section>
    </main>
  );
}

function Wallet() {
  const { address, isConnected, chainId } = useAccount();
  const { connectors, connect, error } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();
  if (!isConnected)
    return (
      <div className="wallet">
        <button onClick={() => connect({ connector: connectors[0]! })}>Connect wallet</button>
        <span className="note">Reading works without a wallet. Connect only to pay or collect.</span>
        {error && <p className="err" role="alert">{friendlyError(error)}</p>}
      </div>
    );
  return (
    <div className="wallet">
      <span>Connected as <code>{shortAddr(address!)}</code></span>
      {chainId !== chain.id && (
        <button onClick={() => switchChain({ chainId: chain.id })}>Switch to {chain.name}</button>
      )}
      <button className="ghost" onClick={() => disconnect()}>Disconnect</button>
    </div>
  );
}

function Sponsor({ address, split, version, onDone }: { address: `0x${string}`; split: Share[]; version: bigint; onDone: () => void }) {
  const [text, setText] = useState("0.01");
  const tx = useTx();
  const { isConnected } = useAccount();
  const wei = parseEthInput(text);
  const preview = useMemo(() => (wei && split.length ? previewDeposit(split, wei) : []), [wei, split]);
  useEffect(() => { if (tx.done) onDone(); }, [tx.done]); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <section aria-labelledby="sponsor-h">
      <h2 id="sponsor-h">Sponsor this project</h2>
      <label htmlFor="amt">Amount in ETH</label>
      <div className="row">
        <input id="amt" inputMode="decimal" value={text} onChange={(e) => { setText(e.target.value); tx.reset(); }} />
        <button
          disabled={!wei || !isConnected || tx.waiting}
          onClick={() => wei && tx.send({ address, abi: splitterAbi, functionName: "fundWithVersion", args: [version], value: wei, chainId: chain.id })}
        >
          Send {wei ? formatEth(wei) : ""}
        </button>
      </div>
      {!wei && text !== "" && <p className="err" role="alert">Enter an amount above 0, like 0.05.</p>}
      {!isConnected && <p className="note">Connect a wallet to pay. You can also send ETH straight to <code>{address}</code>.</p>}
      {wei && preview.length > 0 && (
        <ul className="preview" aria-label="What this payment turns into">
          {split.map((s, i) => (
            <li key={s.account}><span>{s.label || shortAddr(s.account)}</span><span>{formatEth(preview[i]!)}</span></li>
          ))}
        </ul>
      )}
      <TxStatus tx={tx} doneText="Thank you. Your payment is now split between everyone above." />
    </section>
  );
}

function MyMoney({ address, onDone }: { address: `0x${string}`; onDone: () => void }) {
  const { address: me, isConnected } = useAccount();
  const [dest, setDest] = useState("");
  const tx = useTx();
  const { data, refetch } = useReadContracts({
    contracts: me
      ? [
          { address, abi: splitterAbi, functionName: "owed", args: [me], chainId: chain.id },
          { address, abi: splitterAbi, functionName: "totalEarned", args: [me], chainId: chain.id },
        ]
      : [],
    query: { enabled: !!me, refetchInterval: POLL },
  });
  const owed = data?.[0]?.status === "success" ? (data[0].result as bigint) : 0n;
  const earned = data?.[1]?.status === "success" ? (data[1].result as bigint) : 0n;
  useEffect(() => { if (tx.done) { refetch(); onDone(); } }, [tx.done]); // eslint-disable-line react-hooks/exhaustive-deps

  const useDest = dest.trim() !== "";
  const destOk = !useDest || isAddress(dest.trim());

  return (
    <section aria-labelledby="mine-h">
      <h2 id="mine-h">Your money</h2>
      {!isConnected ? (
        <p className="note">Connect your wallet to see what you are owed.</p>
      ) : (
        <>
          <p className="big">You are owed <strong>{formatEth(owed)}</strong></p>
          <p className="note">Earned in total: {formatEth(earned)}. Only you can collect this. Not even the maintainer can.</p>
          <label htmlFor="dest">Send it somewhere else (optional)</label>
          <input id="dest" placeholder="0x… leave empty to receive it in this wallet" value={dest} onChange={(e) => setDest(e.target.value)} />
          {!destOk && <p className="err" role="alert">That is not a valid address.</p>}
          <button
            disabled={owed === 0n || !destOk || tx.waiting}
            onClick={() =>
              useDest
                ? tx.send({ address, abi: splitterAbi, functionName: "withdrawTo", args: [dest.trim() as `0x${string}`], chainId: chain.id })
                : tx.send({ address, abi: splitterAbi, functionName: "withdraw", chainId: chain.id })
            }
          >
            Collect {formatEth(owed)}
          </button>
          <TxStatus tx={tx} doneText="Collected. The money is in your wallet." />
        </>
      )}
    </section>
  );
}

function Lookup({ address }: { address: `0x${string}` }) {
  const [q, setQ] = useState("");
  const ok = isAddress(q.trim());
  const { data } = useReadContracts({
    contracts: ok
      ? [
          { address, abi: splitterAbi, functionName: "owed", args: [q.trim() as `0x${string}`], chainId: chain.id },
          { address, abi: splitterAbi, functionName: "totalEarned", args: [q.trim() as `0x${string}`], chainId: chain.id },
        ]
      : [],
    query: { enabled: ok, refetchInterval: POLL },
  });
  return (
    <section aria-labelledby="look-h">
      <h2 id="look-h">Check anyone's balance</h2>
      <label htmlFor="q">Wallet address</label>
      <input id="q" placeholder="0x…" value={q} onChange={(e) => setQ(e.target.value)} />
      {q !== "" && !ok && <p className="err" role="alert">That is not a valid address.</p>}
      {ok && data?.[0]?.status === "success" && (
        <p>
          Owed now: <strong>{formatEth(data[0].result as bigint)}</strong>. Earned in total:{" "}
          {formatEth((data[1]?.result as bigint | undefined) ?? 0n)}.
        </p>
      )}
    </section>
  );
}

function Pending({
  address, pending, frozen, onDone,
}: { address: `0x${string}`; pending: readonly [readonly Share[], bigint] | undefined; frozen: boolean; onDone: () => void }) {
  const tx = useTx();
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000));
  useEffect(() => { const t = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000); return () => clearInterval(t); }, []);
  useEffect(() => { if (tx.done) onDone(); }, [tx.done]); // eslint-disable-line react-hooks/exhaustive-deps
  const eta = pending ? Number(pending[1]) : 0;
  if (frozen || !pending || eta === 0) return null;
  const left = eta - now;
  const shares = pending[0].map((s) => ({ ...s }));
  return (
    <section aria-labelledby="pend-h">
      <h2 id="pend-h">⚠ A change to the split is proposed</h2>
      <p>It was announced publicly and can take effect in <strong>{timeLeft(left)}</strong>. It only applies to payments made after it takes effect. Money already credited stays exactly as it is.</p>
      <ul className="split">
        {shares.map((s) => (
          <li key={s.account}><span className="who">{s.label || shortAddr(s.account)}</span><span className="pct">{bpsToPercent(Number(s.bps))}</span></li>
        ))}
      </ul>
      <button disabled={left > 0 || tx.waiting} onClick={() => tx.send({ address, abi: splitterAbi, functionName: "activateSplit", chainId: chain.id })}>
        Make this change take effect
      </button>
      <TxStatus tx={tx} doneText="The new split is now active." />
    </section>
  );
}

function Stray({ address, amount, onDone }: { address: `0x${string}`; amount: bigint; onDone: () => void }) {
  const tx = useTx();
  useEffect(() => { if (tx.done) onDone(); }, [tx.done]); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <section aria-labelledby="stray-h">
      <h2 id="stray-h">{formatEth(amount)} arrived without being split</h2>
      <p className="note">ETH can be forced into a contract without it knowing. Anyone can press this button to split it by the current rules.</p>
      <button disabled={tx.waiting} onClick={() => tx.send({ address, abi: splitterAbi, functionName: "sync", chainId: chain.id })}>
        Split it now
      </button>
      <TxStatus tx={tx} doneText="Split between everyone." />
    </section>
  );
}
