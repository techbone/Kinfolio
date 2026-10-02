import { ButtonLink, Card, Pill } from "@/components/ui";

const steps = [
  {
    title: "Write the rules",
    body: "Pick the stock tokens and USDG to cover, name your heirs, and set tranches: 40% now, 30% at 18, a monthly allowance over three years.",
  },
  {
    title: "Keep living",
    body: "Nothing is locked. Your tokens stay in your wallet and you keep trading. Any Kinfolio action you take counts as a check-in.",
  },
  {
    title: "If you go silent",
    body: "After your deadline, an heir can open a claim. One tap from you vetoes it. If no veto comes during the challenge window, the trust settles onchain.",
  },
];

const guarantees = [
  ["No escrow", "The trust holds an allowance, not your assets, and can only use it after release."],
  ["One contract per family", "Your approvals go to your own trust. A bug elsewhere cannot reach them."],
  ["Zero admin keys", "No pause, no upgrade, no fee switch. Nobody can change the rules, including us."],
  ["Splits flow through", "Tranches are counted in raw units, so ERC-8056 splits and dividends reach heirs untouched."],
  ["Pauses can't block heirs", "If an issuer pauses one ticker, every other asset still settles."],
  ["Heirs don't need us", "Anyone can complete settlement from a block explorer. Payouts only go to the heirs you named."],
];

export default function Home() {
  return (
    <div className="space-y-20 pt-6 sm:pt-12">
      <section className="grid items-center gap-10 md:grid-cols-[1.15fr_1fr]">
        <div>
          <Pill tone="brass">Built on Robinhood Chain</Pill>
          <h1 className="mt-4 font-display text-4xl leading-[1.05] tracking-tight sm:text-6xl">
            A family trust for your stock portfolio. <span className="text-brass">Without the lawyer.</span>
          </h1>
          <p className="mt-5 max-w-xl text-base text-muted sm:text-lg">
            Self-custody stock tokens have no transfer-on-death. Kinfolio puts it back: name heirs for your stock
            tokens and USDG, decide who gets what and when, and keep every token in your own wallet while you live.
          </p>
          <div className="mt-8 flex flex-wrap gap-3">
            <ButtonLink href="/create">Create a trust</ButtonLink>
            <ButtonLink href="/trusts" variant="secondary">
              I&apos;ve been named an heir
            </ButtonLink>
          </div>
        </div>
        <ExampleTrust />
      </section>

      <section>
        <h2 className="font-display text-2xl sm:text-3xl">How it works</h2>
        <div className="mt-6 grid gap-4 md:grid-cols-3">
          {steps.map((step, i) => (
            <Card key={step.title}>
              <p className="font-display text-3xl text-brass">{i + 1}</p>
              <h3 className="mt-2 font-medium">{step.title}</h3>
              <p className="mt-2 text-sm text-muted">{step.body}</p>
            </Card>
          ))}
        </div>
      </section>

      <section>
        <h2 className="font-display text-2xl sm:text-3xl">Built to be trusted with a family&apos;s wealth</h2>
        <div className="mt-6 grid gap-x-8 gap-y-6 sm:grid-cols-2 lg:grid-cols-3">
          {guarantees.map(([title, body]) => (
            <div key={title} className="border-t border-line pt-4">
              <h3 className="font-medium">{title}</h3>
              <p className="mt-1 text-sm text-muted">{body}</p>
            </div>
          ))}
        </div>
      </section>

      <footer className="border-t border-line pt-6 text-xs text-muted">
        Kinfolio complements a will; it does not replace legal advice. Contracts are live on Robinhood Chain mainnet; this app runs the testnet demo with short timers.{" "}
        <a className="underline" href="https://github.com/techbone/Kinfolio" target="_blank" rel="noreferrer">
          Source on GitHub
        </a>
        .
      </footer>
    </div>
  );
}

function ExampleTrust() {
  const heirs = [
    { name: "Ada (spouse)", rule: "40% of stocks", when: "At release" },
    { name: "Tomi (son)", rule: "30% of stocks", when: "At 18" },
    { name: "Tomi (son)", rule: "30% of stocks", when: "At 25" },
    { name: "Mama", rule: "All USDG", when: "Monthly, 3 years" },
  ];
  return (
    <Card className="relative shadow-[0_24px_60px_-30px_rgba(30,77,60,0.45)]">
      <div className="flex items-center justify-between">
        <p className="font-display text-lg">The Okafor Family Trust</p>
        <Pill tone="forest">Active</Pill>
      </div>
      <p className="mt-1 text-xs text-muted">TSLA · AMZN · NFLX · USDG, all still in the owner&apos;s wallet</p>
      <div className="mt-5 rounded-xl bg-paper p-4">
        <p className="text-xs text-muted">Claimable by heirs if silent for</p>
        <p className="font-display text-3xl tabular">180 days</p>
        <p className="mt-1 text-xs text-muted">then a 14-day window to veto with one tap</p>
      </div>
      <ul className="mt-5 divide-y divide-line text-sm">
        {heirs.map((h, i) => (
          <li key={i} className="flex items-center justify-between py-2.5">
            <span>{h.name}</span>
            <span className="text-right text-muted">
              {h.rule} · <span className="text-ink">{h.when}</span>
            </span>
          </li>
        ))}
      </ul>
    </Card>
  );
}
