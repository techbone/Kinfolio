"use client";

import { useChainId, useSwitchChain } from "wagmi";

import { supportedChains } from "@/lib/config";
import { useMounted } from "@/lib/hooks";
import { cx } from "./ui";

/** Mainnet for real use, Testnet for the minutes-long demo. Works with or without a wallet. */
export function NetworkSwitcher() {
  const mounted = useMounted();
  const chainId = useChainId();
  const switchChain = useSwitchChain();

  return (
    <div className="inline-flex rounded-full border border-line bg-card p-0.5 text-xs">
      {supportedChains.map((chain) => {
        const active = mounted && chain.id === chainId;
        return (
          <button
            key={chain.id}
            type="button"
            disabled={switchChain.isPending}
            onClick={() => !active && switchChain.mutate({ chainId: chain.id })}
            className={cx(
              "rounded-full px-3 py-1 font-medium transition",
              active ? "bg-forest text-on-forest" : "text-muted hover:text-ink",
            )}
          >
            {chain.testnet ? "Testnet" : "Mainnet"}
          </button>
        );
      })}
    </div>
  );
}
