"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { type Address, isAddress } from "viem";
import { useConnection, useReadContracts } from "wagmi";

import { ConnectButton } from "@/components/connect-button";
import { Button, ButtonLink, Card, Pill, SectionTitle, inputClass } from "@/components/ui";
import { factoryAbi, trustAbi } from "@/lib/abi";
import { deployments, getDeployment, supportedChains } from "@/lib/config";
import { formatCountdown, shortAddress } from "@/lib/format";
import { useMounted, useNow } from "@/lib/hooks";
import type { ChainId } from "@/lib/wagmi";

type Entry = { address: Address; chainId: ChainId };

const STATE = ["Active", "Challenge", "Released", "Closed"] as const;
const tone = { Active: "forest", Challenge: "warn", Released: "brass", Closed: "muted" } as const;

export default function TrustsPage() {
  const mounted = useMounted();
  const router = useRouter();
  const { address: me } = useConnection();
  const [lookup, setLookup] = useState("");

  // Trusts can live on either network: read both factories' indexes.
  const index = useReadContracts({
    contracts: supportedChains.flatMap((c) => [
      { address: deployments[c.id].factory, abi: factoryAbi, functionName: "trustsOf" as const, args: [me!] as const, chainId: c.id },
      { address: deployments[c.id].factory, abi: factoryAbi, functionName: "trustsFor" as const, args: [me!] as const, chainId: c.id },
    ]),
    query: { enabled: Boolean(me), refetchInterval: 8000 },
  });
  const collect = (offset: number): Entry[] =>
    supportedChains.flatMap((c, i) =>
      ((index.data?.[i * 2 + offset]?.result ?? []) as readonly Address[]).map((address) => ({
        address,
        chainId: c.id as ChainId,
      })),
    );
  const owned = collect(0);
  const named = collect(1);

  if (!mounted) return null;

  return (
    <div className="space-y-6 pt-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <h1 className="font-display text-3xl sm:text-4xl">My trusts</h1>
        <ButtonLink href="/create">Create a trust</ButtonLink>
      </div>

      {!me ? (
        <Card>
          <p className="text-muted">Connect a wallet to see trusts you own and trusts that name you as an heir.</p>
          <div className="mt-4">
            <ConnectButton />
          </div>
        </Card>
      ) : (
        <>
          <TrustList title="Trusts you own" empty="You haven't created a trust yet." trusts={owned} />
          <TrustList
            title="Trusts that name you"
            empty="No trust names this wallet as an heir yet."
            trusts={named}
            heir={me}
          />
        </>
      )}

      <Card>
        <SectionTitle title="Open a trust by address">
          Heirs: if someone shared their trust address with you, paste it here. No wallet needed to look.
        </SectionTitle>
        <form
          className="flex flex-col gap-2 sm:flex-row"
          onSubmit={(e) => {
            e.preventDefault();
            if (isAddress(lookup)) router.push(`/trust/${lookup}`);
          }}
        >
          <input
            className={`${inputClass} font-mono`}
            placeholder="0x…"
            value={lookup}
            onChange={(e) => setLookup(e.target.value.trim())}
          />
          <Button type="submit" disabled={!isAddress(lookup)}>
            Open
          </Button>
        </form>
      </Card>
    </div>
  );
}

function TrustList({
  title,
  empty,
  trusts,
  heir,
}: {
  title: string;
  empty: string;
  trusts: Entry[];
  heir?: Address;
}) {
  const now = useNow();
  const views = useReadContracts({
    contracts: trusts.map((t) => ({ address: t.address, abi: trustAbi, functionName: "getTrust" as const, chainId: t.chainId })),
    query: { enabled: trusts.length > 0, refetchInterval: 8000 },
  });

  // The factory index is append-only: hide trusts that no longer name this heir.
  const items = trusts
    .map((entry, i) => ({ ...entry, view: views.data?.[i]?.result }))
    .filter(
      ({ view }) =>
        !heir || !view || view.grants.some((g) => g.beneficiary.toLowerCase() === heir.toLowerCase()),
    );

  return (
    <Card>
      <SectionTitle title={title} />
      {items.length === 0 ? (
        <p className="text-sm text-muted">{empty}</p>
      ) : (
        <ul className="divide-y divide-line">
          {items.map(({ address, chainId, view }) => {
            const state = view ? STATE[view.state] : undefined;
            const deadline = view ? view.lastCheckIn + view.inactivityPeriod - now : 0;
            return (
              <li key={`${chainId}-${address}`}>
                <Link href={`/trust/${address}`} className="flex items-center justify-between gap-4 py-3 hover:opacity-80">
                  <div>
                    <p className="font-mono text-sm">{shortAddress(address)}</p>
                    {view && (
                      <p className="text-xs text-muted">
                        {view.assets.length} assets · {view.grants.length} grants
                        {state === "Active" &&
                          (deadline > 0 ? ` · claimable in ${formatCountdown(deadline)}` : " · claimable now")}
                      </p>
                    )}
                  </div>
                  <div className="flex gap-2">
                    <Pill tone={getDeployment(chainId)?.profile === "production" ? "brass" : "muted"}>
                      {getDeployment(chainId)?.label}
                    </Pill>
                    {state && <Pill tone={tone[state]}>{state}</Pill>}
                  </div>
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </Card>
  );
}
