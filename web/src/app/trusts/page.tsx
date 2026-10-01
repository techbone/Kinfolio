"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { type Address, isAddress } from "viem";
import { useConnection, useReadContracts } from "wagmi";

import { ConnectButton } from "@/components/connect-button";
import { Button, ButtonLink, Card, Pill, SectionTitle, inputClass } from "@/components/ui";
import { factoryAbi, trustAbi } from "@/lib/abi";
import { defaultChain, getDeployment } from "@/lib/config";
import { formatCountdown, shortAddress } from "@/lib/format";
import { useMounted, useNow } from "@/lib/hooks";

const STATE = ["Active", "Challenge", "Released", "Closed"] as const;
const tone = { Active: "forest", Challenge: "warn", Released: "brass", Closed: "muted" } as const;

export default function TrustsPage() {
  const mounted = useMounted();
  const router = useRouter();
  const { address: me, chainId } = useConnection();
  const deployment = getDeployment(chainId) ?? getDeployment(defaultChain.id)!;
  const [lookup, setLookup] = useState("");

  const index = useReadContracts({
    contracts: [
      { address: deployment.factory, abi: factoryAbi, functionName: "trustsOf", args: [me!] },
      { address: deployment.factory, abi: factoryAbi, functionName: "trustsFor", args: [me!] },
    ],
    query: { enabled: Boolean(me), refetchInterval: 8000 },
  });
  const owned = (index.data?.[0]?.result ?? []) as readonly Address[];
  const named = (index.data?.[1]?.result ?? []) as readonly Address[];

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
  trusts: readonly Address[];
  heir?: Address;
}) {
  const now = useNow();
  const views = useReadContracts({
    contracts: trusts.map((t) => ({ address: t, abi: trustAbi, functionName: "getTrust" as const })),
    query: { enabled: trusts.length > 0, refetchInterval: 8000 },
  });

  // The factory index is append-only: hide trusts that no longer name this heir.
  const items = trusts
    .map((address, i) => ({ address, view: views.data?.[i]?.result }))
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
          {items.map(({ address, view }) => {
            const state = view ? STATE[view.state] : undefined;
            const deadline = view ? view.lastCheckIn + view.inactivityPeriod - now : 0;
            return (
              <li key={address}>
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
                  {state && <Pill tone={tone[state]}>{state}</Pill>}
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </Card>
  );
}
