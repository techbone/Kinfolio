"use client";

import { useState } from "react";
import { useConnect, useConnection, useConnectors, useDisconnect, useSwitchChain } from "wagmi";

import { defaultChain, getDeployment } from "@/lib/config";
import { shortAddress } from "@/lib/format";
import { useMounted } from "@/lib/hooks";
import { Button } from "./ui";

export function ConnectButton() {
  const mounted = useMounted();
  const { address, chainId, status } = useConnection();
  const connectors = useConnectors();
  const connect = useConnect();
  const disconnect = useDisconnect();
  const switchChain = useSwitchChain();
  const [open, setOpen] = useState(false);

  if (!mounted) return <Button variant="secondary">Connect wallet</Button>;

  if (status === "connected" && !getDeployment(chainId)) {
    return (
      <Button variant="danger" onClick={() => switchChain.mutate({ chainId: defaultChain.id })}>
        Switch to Robinhood Chain
      </Button>
    );
  }

  if (status === "connected" && address) {
    return (
      <div className="relative">
        <Button variant="secondary" onClick={() => setOpen((o) => !o)}>
          <span className="size-2 rounded-full bg-ok" />
          <span className="font-mono">{shortAddress(address)}</span>
        </Button>
        {open && (
          <div className="absolute right-0 z-20 mt-2 w-44 rounded-xl border border-line bg-card p-1 shadow-lg">
            <button
              className="w-full rounded-lg px-3 py-2 text-left text-sm hover:bg-paper"
              onClick={() => {
                disconnect.mutate();
                setOpen(false);
              }}
            >
              Disconnect
            </button>
          </div>
        )}
      </div>
    );
  }

  if (connectors.length === 0) {
    return (
      <a href="https://metamask.io/download" target="_blank" rel="noreferrer">
        <Button variant="secondary">Install a wallet</Button>
      </a>
    );
  }

  return (
    <div className="relative">
      <Button
        disabled={status === "connecting" || status === "reconnecting"}
        onClick={() =>
          connectors.length === 1
            ? connect.mutate({ connector: connectors[0], chainId: defaultChain.id })
            : setOpen((o) => !o)
        }
      >
        {status === "connecting" ? "Connecting…" : "Connect wallet"}
      </Button>
      {open && (
        <div className="absolute right-0 z-20 mt-2 w-56 rounded-xl border border-line bg-card p-1 shadow-lg">
          {connectors.map((connector) => (
            <button
              key={connector.uid}
              className="flex w-full items-center gap-3 rounded-lg px-3 py-2 text-left text-sm hover:bg-paper"
              onClick={() => {
                connect.mutate({ connector, chainId: defaultChain.id });
                setOpen(false);
              }}
            >
              {connector.icon && <img src={connector.icon} alt="" className="size-5" />}
              {connector.name}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
