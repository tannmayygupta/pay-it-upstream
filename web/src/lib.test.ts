import { describe, expect, it } from "vitest";
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

const A = "0x00000000000000000000000000000000000000a1" as const;
const sh = (bps: number[]): Share[] => bps.map((b, i) => ({ account: A, bps: b, label: `r${i}` }));

describe("bpsToPercent", () => {
  it("formats", () => {
    expect(bpsToPercent(4000)).toBe("40%");
    expect(bpsToPercent(1250)).toBe("12.5%");
    expect(bpsToPercent(1)).toBe("0.01%");
    expect(bpsToPercent(10000)).toBe("100%");
  });
});

describe("formatEth", () => {
  it("formats", () => {
    expect(formatEth(0n)).toBe("0 ETH");
    expect(formatEth(10n ** 18n)).toBe("1 ETH");
    expect(formatEth(1_500_000_000_000_000_000n)).toBe("1.5 ETH");
    expect(formatEth(7n)).toBe("7 wei");
    expect(formatEth(123_456_789_012_345_678n)).toBe("0.123456 ETH");
  });
});

describe("previewDeposit mirrors the contract", () => {
  it("gives the remainder to the last share and conserves the total", () => {
    const out = previewDeposit(sh([4000, 2000, 1000, 2000, 1000]), 7n);
    expect(out).toEqual([2n, 1n, 0n, 1n, 3n]);
    expect(out.reduce((a, b) => a + b, 0n)).toBe(7n);
  });
  it("conserves for many amounts", () => {
    for (const amt of [1n, 2n, 3n, 99n, 10n ** 18n + 1n]) {
      const out = previewDeposit(sh([3333, 3333, 3334]), amt);
      expect(out.reduce((a, b) => a + b, 0n)).toBe(amt);
    }
  });
});

describe("timeLeft", () => {
  it("formats", () => {
    expect(timeLeft(0)).toBe("ready now");
    expect(timeLeft(-5)).toBe("ready now");
    expect(timeLeft(30)).toBe("under a minute");
    expect(timeLeft(45 * 60)).toBe("45 minutes");
    expect(timeLeft(2 * 86400 + 3 * 3600)).toBe("2 days 3 hours");
    expect(timeLeft(86400)).toBe("1 day");
  });
});

describe("parseEthInput", () => {
  it("parses without floats", () => {
    expect(parseEthInput("1")).toBe(10n ** 18n);
    expect(parseEthInput("0.000000000000000001")).toBe(1n);
    expect(parseEthInput(".5")).toBe(5n * 10n ** 17n);
  });
  it("rejects bad input", () => {
    for (const bad of ["", ".", "0", "abc", "-1", "1e3", "1.0000000000000000001", "1.2.3"]) {
      expect(parseEthInput(bad)).toBeNull();
    }
  });
});

describe("friendlyError", () => {
  it("maps contract errors and wallet errors", () => {
    expect(friendlyError(new Error("reverted with NothingToWithdraw"))).toMatch(/nothing to withdraw/i);
    expect(friendlyError(new Error("User rejected the request."))).toMatch(/cancelled/i);
    expect(friendlyError(new Error("insufficient funds for gas"))).toMatch(/enough ETH/i);
    expect(friendlyError(new Error("weird"))).toMatch(/Something went wrong/);
    expect(friendlyError("TransferFailed")).toMatch(/different address/);
  });
});

describe("describeSplit / shortAddr", () => {
  it("describes", () => {
    expect(describeSplit(sh([7000, 3000]))).toEqual(["70% goes to r0", "30% goes to r1"]);
    expect(describeSplit([{ account: A, bps: 10000, label: "" }])[0]).toContain("0x0000");
    expect(shortAddr(A)).toBe("0x0000…00a1");
  });
});
