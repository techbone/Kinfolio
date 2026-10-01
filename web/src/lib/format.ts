import { formatUnits } from "viem";

export const BPS = 10_000;

export function shortAddress(address: string | undefined): string {
  if (!address) return "";
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

export function formatAmount(value: bigint, decimals: number, maxFraction = 4): string {
  const n = Number(formatUnits(value, decimals));
  return n.toLocaleString("en-US", { maximumFractionDigits: maxFraction });
}

export function formatUsd(n: number): string {
  return n.toLocaleString("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });
}

export function formatPercent(bps: number): string {
  const pct = bps / 100;
  return `${Number.isInteger(pct) ? pct : pct.toFixed(2)}%`;
}

export function formatDate(seconds: number | bigint): string {
  return new Date(Number(seconds) * 1000).toLocaleString("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

const UNITS: [string, number][] = [
  ["year", 365 * 86_400],
  ["month", 30 * 86_400],
  ["day", 86_400],
  ["hour", 3_600],
  ["minute", 60],
  ["second", 1],
];

/** "6 months", "2 minutes", "1 year 2 months" (two most significant units). */
export function formatDuration(totalSeconds: number): string {
  if (totalSeconds <= 0) return "0 seconds";
  const parts: string[] = [];
  let rest = Math.floor(totalSeconds);
  for (const [name, size] of UNITS) {
    const count = Math.floor(rest / size);
    if (count > 0) {
      parts.push(`${count} ${name}${count === 1 ? "" : "s"}`);
      rest -= count * size;
    }
    if (parts.length === 2) break;
  }
  return parts.join(" ");
}

/** Compact live countdown: "4d 03:12:09" or "01:59". */
export function formatCountdown(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds));
  const d = Math.floor(s / 86_400);
  const h = Math.floor((s % 86_400) / 3_600);
  const m = Math.floor((s % 3_600) / 60);
  const sec = s % 60;
  const pad = (n: number) => n.toString().padStart(2, "0");
  if (d > 0) return `${d}d ${pad(h)}:${pad(m)}:${pad(sec)}`;
  if (h > 0) return `${pad(h)}:${pad(m)}:${pad(sec)}`;
  return `${pad(m)}:${pad(sec)}`;
}

export const DURATION_UNITS = {
  minutes: 60,
  hours: 3_600,
  days: 86_400,
  months: 30 * 86_400,
  years: 365 * 86_400,
} as const;

export type DurationUnit = keyof typeof DURATION_UNITS;
