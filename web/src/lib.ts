import { formatEther } from "viem";

export type Share = { account: `0x${string}`; bps: number; label: string };

const BPS = 10_000n;

/** 4000 -> "40%", 1250 -> "12.5%", 1 -> "0.01%" */
export function bpsToPercent(bps: number): string {
  const whole = Math.floor(bps / 100);
  const frac = bps % 100;
  if (frac === 0) return `${whole}%`;
  return `${whole}.${String(frac).padStart(2, "0").replace(/0$/, "")}%`;
}

/** Wei -> readable ETH, at most 6 decimals, trailing zeros trimmed. Tiny amounts say so. */
export function formatEth(wei: bigint): string {
  if (wei === 0n) return "0 ETH";
  const s = formatEther(wei);
  const [i = "0", f = ""] = s.split(".");
  const trimmed = f.slice(0, 6).replace(/0+$/, "");
  if (i === "0" && trimmed === "") return `${wei.toString()} wei`;
  return `${trimmed ? `${i}.${trimmed}` : i} ETH`;
}

/**
 * Mirror of the contract's rounding, so the UI shows exactly what a deposit will credit:
 * every share except the last gets floor(amount*bps/10000); the last gets the remainder.
 */
export function previewDeposit(shares: Share[], amount: bigint): bigint[] {
  let distributed = 0n;
  return shares.map((s, i) => {
    if (i === shares.length - 1) return amount - distributed;
    const part = (amount * BigInt(s.bps)) / BPS;
    distributed += part;
    return part;
  });
}

/** "2 days 3 hours", "45 minutes", "ready now" */
export function timeLeft(seconds: number): string {
  if (seconds <= 0) return "ready now";
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const parts: string[] = [];
  if (d) parts.push(`${d} day${d === 1 ? "" : "s"}`);
  if (h) parts.push(`${h} hour${h === 1 ? "" : "s"}`);
  if (!d && m) parts.push(`${m} minute${m === 1 ? "" : "s"}`);
  return parts.length ? parts.join(" ") : "under a minute";
}

/** Parse "0.25" into wei without floating point. Returns null when invalid or not positive. */
export function parseEthInput(text: string): bigint | null {
  const t = text.trim();
  if (!/^\d*\.?\d*$/.test(t) || t === "" || t === ".") return null;
  const [i = "0", f = ""] = t.split(".");
  if (f.length > 18) return null;
  const wei = BigInt(i || "0") * 10n ** 18n + BigInt(f.padEnd(18, "0") || "0");
  return wei > 0n ? wei : null;
}

const MESSAGES: Record<string, string> = {
  ZeroValue: "Send more than 0 ETH.",
  NothingToWithdraw: "You have nothing to withdraw right now.",
  TransferFailed:
    "The payout was refused by the receiving address. Your balance is still safe; try withdrawing to a different address.",
  ZeroAddress: "That address is not valid.",
  SplitNotReady: "The public waiting period for this change has not finished yet.",
  NoPendingSplit: "There is no pending change.",
  SplitIsFrozen: "The split is locked forever.",
  WrongSplitVersion:
    "The split changed while you were paying, so your payment was stopped. Reload the page, check the new split, and try again.",
  OwnableUnauthorizedAccount: "Only the maintainer can do that.",
};

/** Turn a wallet/contract error into one plain sentence. */
export function friendlyError(err: unknown): string {
  const text = err instanceof Error ? `${err.name} ${err.message}` : String(err);
  for (const [name, msg] of Object.entries(MESSAGES)) {
    if (text.includes(name)) return msg;
  }
  if (/user rejected|denied transaction|rejected the request/i.test(text)) return "You cancelled the request in your wallet.";
  if (/insufficient funds/i.test(text)) return "Your wallet does not have enough ETH for this plus network fees.";
  return "Something went wrong. Check your wallet and network, then try again.";
}

export function shortAddr(a: string): string {
  return `${a.slice(0, 6)}…${a.slice(-4)}`;
}

/** One readable sentence per recipient. */
export function describeSplit(shares: Share[]): string[] {
  return shares.map((s) => `${bpsToPercent(s.bps)} goes to ${s.label || shortAddr(s.account)}`);
}
