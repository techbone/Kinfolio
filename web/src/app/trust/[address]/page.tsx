"use client";

import { useParams } from "next/navigation";
import { type Address, erc20Abi, isAddress } from "viem";
import { useConnection, useReadContract, useReadContracts } from "wagmi";

import { ConnectButton } from "@/components/connect-button";
import { TxButton } from "@/components/tx-button";
import { Card, Notice, Pill, SectionTitle, cx } from "@/components/ui";
import { trustAbi } from "@/lib/abi";
import { type Token, defaultChain, getDeployment, tokenOf } from "@/lib/config";
import {
  formatAmount,
  formatCountdown,
  formatDate,
  formatDuration,
  formatPercent,
  formatUsd,
  shortAddress,
} from "@/lib/format";
import { explorerUrl, useMounted, useNow } from "@/lib/hooks";
import { useLabels } from "@/lib/labels";
import type { ChainId } from "@/lib/wagmi";

const STATE = ["Active", "Challenge", "Released", "Closed"] as const;
type StateName = (typeof STATE)[number];
const stateTone = { Active: "forest", Challenge: "warn", Released: "brass", Closed: "muted" } as const;

export default function TrustPage() {
  const params = useParams<{ address: string }>();
  const mounted = useMounted();
  const valid = isAddress(params.address ?? "");
  const trust = (valid ? params.address : undefined) as Address | undefined;

  if (!mounted) return null;
  if (!trust) return <Notice tone="danger">That is not a valid trust address.</Notice>;
  return <TrustView trust={trust} />;
}

function TrustView({ trust }: { trust: Address }) {
  const { address: me, chainId } = useConnection();
  const chain = (getDeployment(chainId) ? chainId : defaultChain.id) as ChainId;
  const now = useNow();
  const label = useLabels(trust);

  const info = useReadContract({
    address: trust,
    abi: trustAbi,
    functionName: "getTrust",
    chainId: chain,
    query: { refetchInterval: 4000 },
  });
  const t = info.data;

  const assets = t?.assets ?? [];
  const grants = t?.grants ?? [];
  const tokens: Token[] = assets.map(
    (a) =>
      tokenOf(chain, a) ?? { address: a, symbol: shortAddress(a), name: "Token", decimals: 18, kind: "stock", demoPrice: 0 },
  );

  const perAsset = useReadContracts({
    contracts: t
      ? assets.flatMap((a) => [
          { address: a, abi: erc20Abi, functionName: "balanceOf" as const, args: [t.owner] as const, chainId: chain },
          { address: a, abi: erc20Abi, functionName: "allowance" as const, args: [t.owner, trust] as const, chainId: chain },
          { address: trust, abi: trustAbi, functionName: "collected" as const, args: [a] as const, chainId: chain },
          { address: a, abi: erc20Abi, functionName: "balanceOf" as const, args: [trust] as const, chainId: chain },
        ])
      : [],
    query: { enabled: Boolean(t), refetchInterval: 4000 },
  });

  const perGrant = useReadContracts({
    contracts: t
      ? grants.flatMap((_, g) =>
          assets.flatMap((a) => [
            { address: trust, abi: trustAbi, functionName: "entitlement" as const, args: [BigInt(g), a] as const, chainId: chain },
            { address: trust, abi: trustAbi, functionName: "claimable" as const, args: [BigInt(g), a] as const, chainId: chain },
            { address: trust, abi: trustAbi, functionName: "distributed" as const, args: [BigInt(g), a] as const, chainId: chain },
          ]),
        )
      : [],
    query: { enabled: Boolean(t), refetchInterval: 4000 },
  });

  const refetch = () => {
    void info.refetch();
    void perAsset.refetch();
    void perGrant.refetch();
  };

  if (info.isError)
    return (
      <Notice tone="danger">
        Couldn&apos;t load a Kinfolio trust at {shortAddress(trust)} on {defaultChain.name}.
      </Notice>
    );
  if (!t) return <p className="pt-10 text-muted">Loading trust…</p>;

  const state: StateName = STATE[t.state];
  const isOwner = me?.toLowerCase() === t.owner.toLowerCase();
  const myGrantIds = grants.flatMap((g, i) => (me && g.beneficiary.toLowerCase() === me.toLowerCase() ? [i] : []));
  const isHeir = myGrantIds.length > 0;

  const num = (i: number) => (perAsset.data?.[i]?.result as bigint | undefined) ?? 0n;
  const rows = tokens.map((token, i) => {
    const balance = num(i * 4);
    const allowance = num(i * 4 + 1);
    const coverage = balance < allowance ? balance : allowance;
    return { token, balance, allowance, coverage, collected: num(i * 4 + 2), held: num(i * 4 + 3) };
  });
  const grantNum = (g: number, a: number, k: number) =>
    (perGrant.data?.[(g * assets.length + a) * 3 + k]?.result as bigint | undefined) ?? 0n;

  const claimableAfter = t.lastCheckIn + t.inactivityPeriod;
  const finalizableAfter = t.claimStartedAt + t.challengeWindow;
  const released = state === "Released";
  const value = rows.reduce((sum, r) => {
    const amount = released ? r.held : r.coverage;
    return sum + (Number(amount) / 10 ** r.token.decimals) * r.token.demoPrice;
  }, 0);
  const uncollected = released ? rows.filter((r) => r.coverage > 0n) : [];

  return (
    <div className="space-y-6 pt-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="text-xs uppercase tracking-[0.14em] text-brass">Family trust</p>
          <h1 className="mt-1 font-display text-3xl sm:text-4xl">
            {isOwner ? "Your trust" : isHeir ? "A trust that names you" : "Kinfolio trust"}
          </h1>
          <a
            href={explorerUrl("address", trust)}
            target="_blank"
            rel="noreferrer"
            className="mt-1 inline-block font-mono text-xs text-muted hover:text-ink"
          >
            {trust} ↗
          </a>
        </div>
        <div className="flex items-center gap-2">
          <Pill tone={stateTone[state]}>{state}</Pill>
          {isOwner && <Pill tone="forest">You are the owner</Pill>}
          {isHeir && <Pill tone="brass">You are an heir</Pill>}
        </div>
      </div>

      {!me && (
        <Notice tone="forest">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <span>Connect a wallet to act as the owner or an heir. Anyone can view and help settle.</span>
            <ConnectButton />
          </div>
        </Notice>
      )}

      <StatusCard
        state={state}
        now={now}
        claimableAfter={claimableAfter}
        finalizableAfter={finalizableAfter}
        releasedAt={t.releasedAt}
        claimant={t.claimant}
        claimantName={label(t.claimant)}
        challengeWindow={t.challengeWindow}
        isOwner={isOwner}
        isHeir={isHeir}
        trust={trust}
        uncollected={uncollected.map((r) => r.token.symbol)}
        onDone={refetch}
      />

      <Card>
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <SectionTitle
            title={released ? "Assets held for heirs" : "What the trust covers"}
          >
            {released
              ? "Collected from the owner's wallet and waiting to be paid out on schedule."
              : "Still in the owner's wallet. Covered = min(balance, approval), pulled only after release."}
          </SectionTitle>
          <p className="font-display text-2xl tabular">
            {formatUsd(value)}
            <span className="ml-1 text-xs text-muted">demo prices</span>
          </p>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[480px] text-sm">
            <thead>
              <tr className="text-left text-xs text-muted">
                <th className="py-2 font-normal">Asset</th>
                {released ? (
                  <>
                    <th className="py-2 text-right font-normal">Collected</th>
                    <th className="py-2 text-right font-normal">Still in trust</th>
                    <th className="py-2 text-right font-normal">Left in owner wallet</th>
                  </>
                ) : (
                  <>
                    <th className="py-2 text-right font-normal">Owner balance</th>
                    <th className="py-2 text-right font-normal">Covered</th>
                    <th className="py-2 text-right font-normal" />
                  </>
                )}
              </tr>
            </thead>
            <tbody className="divide-y divide-line">
              {rows.map((r) => (
                <tr key={r.token.address}>
                  <td className="py-3">
                    <span className="font-medium">{r.token.symbol}</span>
                    {r.token.kind === "cash" && t.hasCashSleeve && (
                      <span className="ml-2 text-xs text-muted">allowance</span>
                    )}
                  </td>
                  {released ? (
                    <>
                      <td className="py-3 text-right tabular">{formatAmount(r.collected, r.token.decimals)}</td>
                      <td className="py-3 text-right tabular">{formatAmount(r.held, r.token.decimals)}</td>
                      <td className="py-3 text-right tabular text-muted">{formatAmount(r.coverage, r.token.decimals)}</td>
                    </>
                  ) : (
                    <>
                      <td className="py-3 text-right tabular">{formatAmount(r.balance, r.token.decimals)}</td>
                      <td className="py-3 text-right tabular">
                        {r.balance > 0n && r.coverage >= r.balance ? (
                          <span className="text-ok">Fully covered</span>
                        ) : (
                          formatAmount(r.coverage, r.token.decimals)
                        )}
                      </td>
                      <td className="py-3 text-right">
                        {isOwner && state === "Active" && r.allowance < r.balance && (
                          <TxButton
                            variant="secondary"
                            label="Approve"
                            call={{
                              address: r.token.address,
                              abi: erc20Abi,
                              functionName: "approve",
                              args: [trust, 2n ** 256n - 1n],
                            }}
                            onConfirmed={refetch}
                          />
                        )}
                      </td>
                    </>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>

      <Card>
        <SectionTitle title="Heirs and tranches">
          Payouts only ever go to these addresses. Anyone can trigger them; nobody can redirect them.
        </SectionTitle>
        <div className="space-y-3">
          {grants.map((g, gi) => {
            const mine = myGrantIds.includes(gi);
            const start = Math.max(t.releasedAt, g.unlockAt);
            const pending = assets.some((_, ai) => grantNum(gi, ai, 1) > 0n);
            const owed = assets.some((_, ai) => grantNum(gi, ai, 0) > grantNum(gi, ai, 2));
            const fullyPaid = !owed && assets.some((_, ai) => grantNum(gi, ai, 2) > 0n);
            return (
              <div
                key={gi}
                className={cx("rounded-xl border p-4", mine ? "border-brass bg-brass-soft/40" : "border-line bg-paper")}
              >
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <p className="font-medium">
                      {label(g.beneficiary) ?? shortAddress(g.beneficiary)}
                      {mine && <span className="ml-2 text-xs text-brass">(you)</span>}
                    </p>
                    <p className="font-mono text-xs text-muted">{shortAddress(g.beneficiary)}</p>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    <Pill tone={g.sleeve === 1 ? "brass" : "forest"}>
                      {formatPercent(g.bps)} of {g.sleeve === 1 ? "USDG" : "portfolio"}
                    </Pill>
                    <Pill>
                      {g.unlockAt > 0 ? `Unlocks ${formatDate(g.unlockAt)}` : "At settlement"}
                    </Pill>
                    <Pill>{g.vestDuration > 0 ? `Gradually over ${formatDuration(g.vestDuration)}` : "All at once"}</Pill>
                  </div>
                </div>

                {released && (
                  <div className="mt-3 border-t border-line pt-3">
                    <div className="grid gap-x-6 gap-y-1 text-sm sm:grid-cols-2">
                      {tokens.map((token, ai) => {
                        const total = grantNum(gi, ai, 0);
                        if (total === 0n) return null;
                        return (
                          <p key={token.address} className="flex justify-between tabular">
                            <span className="text-muted">{token.symbol}</span>
                            <span>
                              {formatAmount(grantNum(gi, ai, 2), token.decimals)} paid ·{" "}
                              <span className="text-ok">{formatAmount(grantNum(gi, ai, 1), token.decimals)} ready</span>{" "}
                              <span className="text-muted">/ {formatAmount(total, token.decimals)}</span>
                            </span>
                          </p>
                        );
                      })}
                    </div>
                    <div className="mt-3 flex flex-wrap items-center gap-3">
                      {fullyPaid ? (
                        <Pill tone="forest">✓ Fully paid{mine ? " to you" : ""}</Pill>
                      ) : pending ? (
                        <TxButton
                          variant={mine ? "primary" : "secondary"}
                          label={mine ? "Withdraw what's ready" : "Pay out what's ready"}
                          disabled={!me}
                          call={{ address: trust, abi: trustAbi, functionName: "distributeAll", args: [BigInt(gi)] }}
                          onConfirmed={refetch}
                        />
                      ) : (
                        <span className="text-xs text-muted">
                          {now < start ? `Next unlock ${formatDate(start)}` : "Paying out gradually; check back soon"}
                        </span>
                      )}
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </Card>

      <Card>
        <SectionTitle title="Rules" />
        <dl className="grid gap-4 text-sm sm:grid-cols-3">
          <div>
            <dt className="text-xs text-muted">Owner</dt>
            <dd className="font-mono">{shortAddress(t.owner)}</dd>
          </div>
          <div>
            <dt className="text-xs text-muted">Claimable after silence of</dt>
            <dd>{formatDuration(t.inactivityPeriod)}</dd>
          </div>
          <div>
            <dt className="text-xs text-muted">Veto window</dt>
            <dd>{formatDuration(t.challengeWindow)}</dd>
          </div>
        </dl>
        {isOwner && state === "Active" && (
          <div className="mt-5 border-t border-line pt-4">
            <TxButton
              variant="danger"
              label="Close this trust permanently"
              call={{ address: trust, abi: trustAbi, functionName: "close" }}
              onConfirmed={refetch}
            />
            <p className="mt-1 text-xs text-muted">A closed trust can never pull funds. Revoke approvals afterwards.</p>
          </div>
        )}
      </Card>
    </div>
  );
}

function StatusCard(props: {
  state: StateName;
  now: number;
  claimableAfter: number;
  finalizableAfter: number;
  releasedAt: number;
  claimant: Address;
  claimantName?: string;
  challengeWindow: number;
  isOwner: boolean;
  isHeir: boolean;
  trust: Address;
  uncollected: string[];
  onDone: () => void;
}) {
  const { state, now, trust, isOwner, isHeir, onDone } = props;
  const checkIn = { address: trust, abi: trustAbi, functionName: "checkIn" } as const;

  if (state === "Active") {
    const left = props.claimableAfter - now;
    const open = left < 0;
    return (
      <Card className={cx(open && "border-warn")}>
        <div className="flex flex-wrap items-center justify-between gap-6">
          <div>
            <p className="text-sm text-muted">
              {open ? "The owner has been silent past the deadline" : "Heirs can open a claim in"}
            </p>
            <p className="font-display text-5xl tabular">{open ? "Claimable" : formatCountdown(left)}</p>
            <p className="mt-1 text-xs text-muted">
              Deadline {formatDate(props.claimableAfter)}. Any owner action resets it.
            </p>
          </div>
          <div className="flex flex-wrap gap-3">
            {isOwner && <TxButton label="I'm alive — check in" call={checkIn} onConfirmed={onDone} />}
            {isHeir && (
              <TxButton
                variant={open ? "primary" : "secondary"}
                label="Open a claim"
                disabled={!open}
                call={{ address: trust, abi: trustAbi, functionName: "startClaim" }}
                onConfirmed={onDone}
              />
            )}
          </div>
        </div>
      </Card>
    );
  }

  if (state === "Challenge") {
    const left = props.finalizableAfter - now;
    const done = left < 0;
    return (
      <Card className="border-warn">
        <div className="flex flex-wrap items-center justify-between gap-6">
          <div>
            <p className="text-sm text-warn">
              Claim opened by {props.claimantName ?? shortAddress(props.claimant)}
            </p>
            <p className="font-display text-5xl tabular">{done ? "Ready to settle" : formatCountdown(left)}</p>
            <p className="mt-1 text-xs text-muted">
              {done
                ? "The veto window passed without the owner responding. Anyone can settle the trust."
                : "The trust settles when this window ends, unless the owner vetoes with one tap."}
            </p>
          </div>
          <div className="flex flex-wrap gap-3">
            {isOwner && !done && <TxButton variant="danger" label="Veto — I'm alive" call={checkIn} onConfirmed={onDone} />}
            {(done || !isOwner) && (
              <TxButton
                label="Settle trust"
                disabled={!done}
                call={{ address: trust, abi: trustAbi, functionName: "finalize" }}
                onConfirmed={onDone}
              />
            )}
          </div>
        </div>
      </Card>
    );
  }

  if (state === "Released") {
    return (
      <Card className="border-brass">
        <div className="flex flex-wrap items-center justify-between gap-6">
          <div>
            <p className="text-sm text-brass">Settled {formatDate(props.releasedAt)}</p>
            <p className="font-display text-3xl">The trust is now paying out</p>
            <p className="mt-1 text-xs text-muted">
              {props.uncollected.length > 0
                ? `${props.uncollected.join(", ")} still to collect from the owner's wallet.`
                : "Everything covered has been collected. Tranches pay out as they unlock."}
            </p>
          </div>
          {props.uncollected.length > 0 && (
            <TxButton
              label="Collect assets"
              call={{ address: trust, abi: trustAbi, functionName: "collectAll" }}
              onConfirmed={onDone}
            />
          )}
        </div>
      </Card>
    );
  }

  return (
    <Card>
      <p className="font-display text-2xl">This trust was closed by its owner.</p>
      <p className="mt-1 text-sm text-muted">It can never pull funds again.</p>
    </Card>
  );
}
