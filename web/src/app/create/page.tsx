"use client";

import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { type Address, erc20Abi, isAddress, maxUint256, toHex } from "viem";
import { useConnection, useReadContracts } from "wagmi";
import { readContract, waitForTransactionReceipt, writeContract } from "wagmi/actions";

import { ConnectButton } from "@/components/connect-button";
import { Button, Card, Field, Notice, Pill, SectionTitle, cx, inputClass } from "@/components/ui";
import { factoryAbi, trustAbi } from "@/lib/abi";
import { type Token, getDeployment } from "@/lib/config";
import { BPS, DURATION_UNITS, type DurationUnit, formatAmount, formatDuration, formatUsd } from "@/lib/format";
import { errorMessage, useMounted } from "@/lib/hooks";
import { saveLabels } from "@/lib/labels";
import { wagmiConfig } from "@/lib/wagmi";

type Sleeve = 0 | 1; // Portfolio | Cash

type HeirRow = {
  id: number;
  name: string;
  address: string;
  percent: string;
  unlock: "release" | "in" | "date";
  inValue: string;
  inUnit: DurationUnit;
  date: string;
  paid: "once" | "gradual";
  vestValue: string;
  vestUnit: DurationUnit;
};

type Span = { value: string; unit: DurationUnit };
type StepStatus = "waiting" | "active" | "done" | "failed";
type Step = { key: string; label: string; status: StepStatus };

let nextId = 1;
function row(partial: Partial<HeirRow>): HeirRow {
  return {
    id: nextId++,
    name: "",
    address: "",
    percent: "",
    unlock: "release",
    inValue: "",
    inUnit: "years",
    date: "",
    paid: "once",
    vestValue: "",
    vestUnit: "months",
    ...partial,
  };
}

const seconds = (s: Span) => Math.round(Number(s.value || 0) * DURATION_UNITS[s.unit]);
const toBps = (percent: string) => Math.round(Number(percent || 0) * 100);

function unlockAt(r: HeirRow, now: number): number {
  if (r.unlock === "in") return now + seconds({ value: r.inValue, unit: r.inUnit });
  if (r.unlock === "date" && r.date) return Math.floor(new Date(r.date).getTime() / 1000);
  return 0;
}

const vestDuration = (r: HeirRow) => (r.paid === "gradual" ? seconds({ value: r.vestValue, unit: r.vestUnit }) : 0);

function describe(r: HeirRow, what: string): string {
  const who = r.name || "This heir";
  const share = `${r.percent || 0}% of ${what}`;
  const when =
    r.unlock === "release"
      ? "when the trust settles"
      : r.unlock === "in"
        ? `from ${formatDuration(seconds({ value: r.inValue, unit: r.inUnit }))} after today (or at settlement, if later)`
        : `from ${r.date ? new Date(r.date).toLocaleDateString("en-GB", { dateStyle: "long" }) : "a date"} (or at settlement, if later)`;
  const how =
    r.paid === "gradual" ? `, paid out gradually over ${formatDuration(vestDuration(r))}` : ", all at once";
  return `${who} receives ${share} ${when}${how}.`;
}

export default function CreatePage() {
  const mounted = useMounted();
  const router = useRouter();
  const { address: owner, chainId, status } = useConnection();
  const deployment = getDeployment(chainId);
  const demo = deployment?.profile !== "production";

  const [selected, setSelected] = useState<Set<string> | null>(null);
  const [portfolio, setPortfolio] = useState<HeirRow[]>(() => [
    row({ name: "Spouse", percent: "40" }),
    row({ name: "Child", percent: "30", unlock: "in", inValue: "5", inUnit: "minutes" }),
    row({ name: "Child", percent: "30", unlock: "in", inValue: "10", inUnit: "minutes" }),
  ]);
  const [allowanceOn, setAllowanceOn] = useState(true);
  const [allowance, setAllowance] = useState<HeirRow[]>(() => [
    row({ name: "Parent", percent: "100", paid: "gradual", vestValue: "10", vestUnit: "minutes" }),
  ]);
  const [inactivity, setInactivity] = useState<Span>({ value: "2", unit: "minutes" });
  const [challenge, setChallenge] = useState<Span>({ value: "1", unit: "minutes" });
  const [steps, setSteps] = useState<Step[]>([]);
  const [failure, setFailure] = useState<string>();
  const [created, setCreated] = useState<Address>();

  const tokens = deployment?.tokens ?? [];
  const reads = useReadContracts({
    contracts: [
      ...tokens.map((t) => ({
        address: t.address,
        abi: erc20Abi,
        functionName: "balanceOf" as const,
        args: [owner ?? "0x0000000000000000000000000000000000000000"] as const,
      })),
      ...(deployment
        ? [
            { address: deployment.implementation, abi: trustAbi, functionName: "MIN_INACTIVITY" as const },
            { address: deployment.implementation, abi: trustAbi, functionName: "MIN_CHALLENGE" as const },
          ]
        : []),
    ],
    query: { enabled: Boolean(owner && deployment) },
  });

  const balances = tokens.map((_, i) => (reads.data?.[i]?.result as bigint | undefined) ?? 0n);
  const minInactivity = Number(reads.data?.[tokens.length]?.result ?? 0);
  const minChallenge = Number(reads.data?.[tokens.length + 1]?.result ?? 0);

  // Default selection: every token the wallet actually holds.
  const chosen = useMemo(() => {
    if (selected) return selected;
    return new Set(tokens.filter((_, i) => balances[i] > 0n).map((t) => t.address));
  }, [selected, tokens, balances]);

  const cash = tokens.find((t) => t.kind === "cash");
  const cashChosen = Boolean(cash && chosen.has(cash.address));
  const useAllowance = allowanceOn && cashChosen;
  const stocksChosen = tokens.filter((t) => t.kind === "stock" && chosen.has(t.address));

  const coveredValue = tokens.reduce(
    (sum, t, i) => (chosen.has(t.address) ? sum + Number(balances[i]) / 10 ** t.decimals * t.demoPrice : sum),
    0,
  );

  const errors = validate();
  const busy = steps.some((s) => s.status === "active");

  function validate(): string[] {
    const out: string[] = [];
    if (chosen.size === 0) out.push("Choose at least one asset to cover.");
    const check = (rows: HeirRow[], label: string) => {
      const total = rows.reduce((s, r) => s + toBps(r.percent), 0);
      if (rows.length === 0) out.push(`Add at least one heir to the ${label}.`);
      if (total !== BPS) out.push(`${label} shares add up to ${total / 100}%, they must total 100%.`);
      rows.forEach((r, i) => {
        const who = r.name || `${label} heir ${i + 1}`;
        if (!isAddress(r.address)) out.push(`${who}: enter a valid wallet address.`);
        else if (owner && r.address.toLowerCase() === owner.toLowerCase())
          out.push(`${who}: you can't name yourself as an heir.`);
        if (toBps(r.percent) <= 0) out.push(`${who}: share must be above 0%.`);
        if (r.unlock === "date" && !r.date) out.push(`${who}: pick an unlock date.`);
        if (r.unlock === "in" && !(Number(r.inValue) > 0)) out.push(`${who}: set how long until it unlocks.`);
        if (r.paid === "gradual" && !(Number(r.vestValue) > 0)) out.push(`${who}: set how long the payout lasts.`);
      });
    };
    check(portfolio, "Portfolio");
    if (useAllowance) check(allowance, "Allowance");
    if (portfolio.length + (useAllowance ? allowance.length : 0) > 12) out.push("A trust holds at most 12 grants.");
    if (minInactivity && seconds(inactivity) < minInactivity)
      out.push(`Inactivity period must be at least ${formatDuration(minInactivity)}.`);
    if (minChallenge && seconds(challenge) < minChallenge)
      out.push(`Challenge window must be at least ${formatDuration(minChallenge)}.`);
    return out;
  }

  async function create() {
    if (!owner || !deployment || errors.length) return;
    setFailure(undefined);
    const assets = tokens.filter((t) => chosen.has(t.address));
    const plan: Step[] = [
      { key: "deploy", label: "Create your trust contract", status: "waiting" },
      ...assets.map((t) => ({ key: t.address, label: `Allow the trust to cover ${t.symbol}`, status: "waiting" as const })),
    ];
    setSteps(plan);
    const mark = (key: string, status: StepStatus) =>
      setSteps((prev) => prev.map((s) => (s.key === key ? { ...s, status } : s)));

    const now = Math.floor(Date.now() / 1000);
    const toGrant = (r: HeirRow, sleeve: Sleeve) => ({
      beneficiary: r.address as Address,
      bps: toBps(r.percent),
      unlockAt: unlockAt(r, now),
      vestDuration: vestDuration(r),
      sleeve,
    });
    const grants = [...portfolio.map((r) => toGrant(r, 0)), ...(useAllowance ? allowance.map((r) => toGrant(r, 1)) : [])];
    const config = {
      inactivityPeriod: seconds(inactivity),
      challengeWindow: seconds(challenge),
      assets: assets.map((t) => t.address),
      grants,
    };

    let current = "deploy";
    try {
      const salt = toHex(crypto.getRandomValues(new Uint8Array(32)));
      const trust = await readContract(wagmiConfig, {
        address: deployment.factory,
        abi: factoryAbi,
        functionName: "predictTrust",
        args: [owner, salt],
      });

      mark("deploy", "active");
      const hash = await writeContract(wagmiConfig, {
        address: deployment.factory,
        abi: factoryAbi,
        functionName: "createTrust",
        args: [config, salt],
      });
      const receipt = await waitForTransactionReceipt(wagmiConfig, { hash });
      if (receipt.status !== "success") throw new Error("Trust creation reverted");
      mark("deploy", "done");
      setCreated(trust);
      saveLabels(
        trust,
        Object.fromEntries([...portfolio, ...allowance].filter((r) => r.name).map((r) => [r.address, r.name])),
      );

      for (const t of assets) {
        current = t.address;
        mark(t.address, "active");
        const approval = await writeContract(wagmiConfig, {
          address: t.address,
          abi: erc20Abi,
          functionName: "approve",
          args: [trust, maxUint256],
        });
        await waitForTransactionReceipt(wagmiConfig, { hash: approval });
        mark(t.address, "done");
      }
      router.push(`/trust/${trust}`);
    } catch (error) {
      mark(current, "failed");
      setFailure(errorMessage(error));
    }
  }

  if (!mounted) return null;

  if (status !== "connected" || !deployment) {
    return (
      <div className="mx-auto mt-16 max-w-md text-center">
        <h1 className="font-display text-3xl">Create a family trust</h1>
        <p className="mt-3 text-muted">Connect the wallet that holds your stock tokens on Robinhood Chain.</p>
        <div className="mt-6 flex justify-center">
          <ConnectButton />
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6 pt-4">
      <div>
        <h1 className="font-display text-3xl sm:text-4xl">Create a family trust</h1>
        <p className="mt-2 max-w-2xl text-muted">
          Nothing leaves your wallet. You&apos;ll sign one transaction to create your trust, then one approval per asset
          so it can act if you go silent.
        </p>
        {demo && (
          <div className="mt-3">
            <Pill tone="warn">Testnet demo: timers can be minutes so you can see the whole lifecycle</Pill>
          </div>
        )}
      </div>

      <Card>
        <SectionTitle eyebrow="Step 1" title="What should the trust cover?">
          Pre-selected from your wallet. Coverage follows your balance, so trading later is fine.
        </SectionTitle>
        <div className="grid gap-2 sm:grid-cols-2">
          {tokens.map((t, i) => (
            <AssetToggle
              key={t.address}
              token={t}
              balance={balances[i]}
              on={chosen.has(t.address)}
              onToggle={() => {
                const next = new Set(chosen);
                if (next.has(t.address)) next.delete(t.address);
                else next.add(t.address);
                setSelected(next);
              }}
            />
          ))}
        </div>
        <p className="mt-4 text-sm text-muted">
          Covered today: <span className="font-medium text-ink">{formatUsd(coveredValue)}</span>
          {demo && " (demo prices)"}
        </p>
      </Card>

      <Card>
        <SectionTitle eyebrow="Step 2" title="Who gets the portfolio?">
          {stocksChosen.length > 0
            ? `Shares of ${stocksChosen.map((t) => t.symbol).join(", ")}${cashChosen && !useAllowance ? " and USDG" : ""}. Add a heir twice to give them separate tranches.`
            : "Shares of every covered asset."}
        </SectionTitle>
        <HeirRows rows={portfolio} onChange={setPortfolio} />
      </Card>

      {cashChosen && (
        <Card>
          <div className="flex flex-wrap items-start justify-between gap-3">
            <SectionTitle eyebrow="Optional" title="A USDG allowance">
              Pay your USDG as a steady allowance, separate from the stock split. Stocks for the long term, dollars
              for the monthly bills.
            </SectionTitle>
            <Button variant="secondary" onClick={() => setAllowanceOn((v) => !v)}>
              {allowanceOn ? "Remove allowance" : "Add allowance"}
            </Button>
          </div>
          {allowanceOn ? (
            <HeirRows rows={allowance} onChange={setAllowance} />
          ) : (
            <p className="text-sm text-muted">Without an allowance, USDG is split like the portfolio above.</p>
          )}
        </Card>
      )}

      <Card>
        <SectionTitle eyebrow="Step 3" title="When can heirs claim?">
          Any Kinfolio action you take resets the clock. A claim never pays out straight away: you always get a
          challenge window to veto it with one tap.
        </SectionTitle>
        <div className="grid gap-4 sm:grid-cols-2">
          <SpanInput
            label="If I'm silent for"
            hint={minInactivity ? `Minimum ${formatDuration(minInactivity)} on this network` : undefined}
            span={inactivity}
            onChange={setInactivity}
          />
          <SpanInput
            label="Then give me a veto window of"
            hint={minChallenge ? `Minimum ${formatDuration(minChallenge)} on this network` : undefined}
            span={challenge}
            onChange={setChallenge}
          />
        </div>
      </Card>

      <Card>
        <SectionTitle eyebrow="Step 4" title="Review" />
        <div className="space-y-2 text-sm">
          <p>
            If you don&apos;t use Kinfolio for <b>{formatDuration(seconds(inactivity))}</b>, any heir can open a claim.
            You then have <b>{formatDuration(seconds(challenge))}</b> to veto it. If you don&apos;t, the trust settles:
          </p>
          <ul className="list-disc space-y-1 pl-5 text-muted">
            {portfolio.map((r) => (
              <li key={r.id}>
                {describe(
                  r,
                  `${stocksChosen.map((t) => t.symbol).join(", ") || "the portfolio"}${cashChosen && !useAllowance ? " and USDG" : ""}`,
                )}
              </li>
            ))}
            {useAllowance && allowance.map((r) => <li key={r.id}>{describe(r, "the USDG")}</li>)}
          </ul>
        </div>

        {errors.length > 0 && (
          <ul className="mt-4 space-y-1 text-sm text-danger">
            {errors.map((e) => (
              <li key={e}>• {e}</li>
            ))}
          </ul>
        )}

        {steps.length > 0 && (
          <ol className="mt-5 space-y-2">
            {steps.map((s) => (
              <li key={s.key} className="flex items-center gap-3 text-sm">
                <StepDot status={s.status} />
                <span className={cx(s.status === "waiting" && "text-muted")}>{s.label}</span>
              </li>
            ))}
          </ol>
        )}

        {failure && (
          <div className="mt-4 space-y-2">
            <Notice tone="danger">{failure}</Notice>
            {created && (
              <p className="text-sm text-muted">
                Your trust exists. You can finish approvals from{" "}
                <a className="underline" href={`/trust/${created}`}>
                  its page
                </a>
                .
              </p>
            )}
          </div>
        )}

        <div className="mt-6 flex flex-wrap items-center gap-3">
          <Button onClick={create} disabled={errors.length > 0 || busy || Boolean(created)}>
            {busy ? "Waiting for your wallet…" : "Create trust"}
          </Button>
          <p className="text-xs text-muted">
            You can change heirs, shares and timers later. Every change counts as a check-in.
          </p>
        </div>
      </Card>
    </div>
  );
}

function AssetToggle({ token, balance, on, onToggle }: { token: Token; balance: bigint; on: boolean; onToggle: () => void }) {
  return (
    <button
      type="button"
      onClick={onToggle}
      className={cx(
        "flex items-center justify-between rounded-xl border px-4 py-3 text-left transition",
        on ? "border-forest bg-forest-soft" : "border-line bg-paper hover:border-muted",
      )}
    >
      <span>
        <span className="font-medium">{token.symbol}</span>
        <span className="ml-2 text-xs text-muted">{token.name}</span>
      </span>
      <span className="text-sm tabular text-muted">{formatAmount(balance, token.decimals)}</span>
    </button>
  );
}

function HeirRows({ rows, onChange }: { rows: HeirRow[]; onChange: (rows: HeirRow[]) => void }) {
  const update = (id: number, patch: Partial<HeirRow>) => onChange(rows.map((r) => (r.id === id ? { ...r, ...patch } : r)));
  const total = rows.reduce((s, r) => s + toBps(r.percent), 0);
  return (
    <div className="space-y-3">
      {rows.map((r) => (
        <div key={r.id} className="rounded-xl border border-line bg-paper p-3 sm:p-4">
          <div className="grid gap-3 sm:grid-cols-[1fr_2fr_90px]">
            <Field label="Name (private, this browser only)">
              <input className={inputClass} value={r.name} onChange={(e) => update(r.id, { name: e.target.value })} />
            </Field>
            <Field label="Wallet address">
              <input
                className={cx(inputClass, "font-mono")}
                placeholder="0x…"
                value={r.address}
                onChange={(e) => update(r.id, { address: e.target.value.trim() })}
              />
            </Field>
            <Field label="Share %">
              <input
                className={cx(inputClass, "tabular")}
                inputMode="decimal"
                value={r.percent}
                onChange={(e) => update(r.id, { percent: e.target.value })}
              />
            </Field>
          </div>
          <div className="mt-3 grid gap-3 sm:grid-cols-2">
            <Field label="Unlocks">
              <div className="flex gap-2">
                <select
                  className={inputClass}
                  value={r.unlock}
                  onChange={(e) => update(r.id, { unlock: e.target.value as HeirRow["unlock"] })}
                >
                  <option value="release">When the trust settles</option>
                  <option value="in">After a waiting period</option>
                  <option value="date">On a date</option>
                </select>
                {r.unlock === "in" && (
                  <SpanFields
                    span={{ value: r.inValue, unit: r.inUnit }}
                    onChange={(s) => update(r.id, { inValue: s.value, inUnit: s.unit })}
                  />
                )}
                {r.unlock === "date" && (
                  <input
                    type="date"
                    className={inputClass}
                    value={r.date}
                    onChange={(e) => update(r.id, { date: e.target.value })}
                  />
                )}
              </div>
            </Field>
            <Field label="Paid">
              <div className="flex gap-2">
                <select
                  className={inputClass}
                  value={r.paid}
                  onChange={(e) => update(r.id, { paid: e.target.value as HeirRow["paid"] })}
                >
                  <option value="once">All at once</option>
                  <option value="gradual">Gradually, over</option>
                </select>
                {r.paid === "gradual" && (
                  <SpanFields
                    span={{ value: r.vestValue, unit: r.vestUnit }}
                    onChange={(s) => update(r.id, { vestValue: s.value, vestUnit: s.unit })}
                  />
                )}
              </div>
            </Field>
          </div>
          {rows.length > 1 && (
            <button
              type="button"
              className="mt-3 text-xs text-muted hover:text-danger"
              onClick={() => onChange(rows.filter((x) => x.id !== r.id))}
            >
              Remove
            </button>
          )}
        </div>
      ))}
      <div className="flex items-center justify-between">
        <Button variant="secondary" onClick={() => onChange([...rows, row({})])}>
          + Add heir or tranche
        </Button>
        <span className={cx("text-sm tabular", total === BPS ? "text-ok" : "text-danger")}>
          Total {total / 100}%
        </span>
      </div>
    </div>
  );
}

function SpanFields({ span, onChange }: { span: Span; onChange: (s: Span) => void }) {
  return (
    <>
      <input
        className={cx(inputClass, "w-20 tabular")}
        inputMode="decimal"
        value={span.value}
        onChange={(e) => onChange({ ...span, value: e.target.value })}
      />
      <select
        className={cx(inputClass, "w-28")}
        value={span.unit}
        onChange={(e) => onChange({ ...span, unit: e.target.value as DurationUnit })}
      >
        {Object.keys(DURATION_UNITS).map((u) => (
          <option key={u} value={u}>
            {u}
          </option>
        ))}
      </select>
    </>
  );
}

function SpanInput({ label, hint, span, onChange }: { label: string; hint?: string; span: Span; onChange: (s: Span) => void }) {
  return (
    <Field label={label} hint={hint}>
      <div className="flex gap-2">
        <SpanFields span={span} onChange={onChange} />
      </div>
    </Field>
  );
}

function StepDot({ status }: { status: StepStatus }) {
  const style = {
    waiting: "border border-line",
    active: "animate-pulse bg-brass",
    done: "bg-ok",
    failed: "bg-danger",
  }[status];
  return <span className={cx("inline-block size-3 rounded-full", style)} />;
}
