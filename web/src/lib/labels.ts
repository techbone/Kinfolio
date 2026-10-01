"use client";

import { useCallback, useEffect, useState } from "react";

// Heir names never go onchain. They live only in this browser, keyed by trust.
const key = (trust: string) => `kinfolio:labels:${trust.toLowerCase()}`;

export function saveLabels(trust: string, labels: Record<string, string>) {
  try {
    const lower = Object.fromEntries(
      Object.entries(labels).map(([address, name]) => [address.toLowerCase(), name]),
    );
    localStorage.setItem(key(trust), JSON.stringify(lower));
  } catch {
    // storage unavailable: names are a convenience only
  }
}

export function useLabels(trust: string | undefined) {
  const [labels, setLabels] = useState<Record<string, string>>({});

  useEffect(() => {
    if (!trust) return;
    try {
      setLabels(JSON.parse(localStorage.getItem(key(trust)) ?? "{}"));
    } catch {
      setLabels({});
    }
  }, [trust]);

  return useCallback((address: string) => labels[address.toLowerCase()], [labels]);
}
