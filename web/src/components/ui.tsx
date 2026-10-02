import Link from "next/link";
import type { ComponentProps, ReactNode } from "react";

const cx = (...parts: (string | false | undefined)[]) => parts.filter(Boolean).join(" ");

export function Card({ className, children }: { className?: string; children: ReactNode }) {
  return (
    <section className={cx("rounded-2xl border border-line bg-card p-5 sm:p-6", className)}>
      {children}
    </section>
  );
}

export function SectionTitle({ eyebrow, title, children }: { eyebrow?: string; title: string; children?: ReactNode }) {
  return (
    <div className="mb-4">
      {eyebrow && (
        <p className="mb-1 text-xs font-medium uppercase tracking-[0.14em] text-brass">{eyebrow}</p>
      )}
      <h2 className="font-display text-xl text-ink sm:text-2xl">{title}</h2>
      {children && <p className="mt-1 text-sm text-muted">{children}</p>}
    </div>
  );
}

type Variant = "primary" | "secondary" | "danger" | "ghost";

const variants: Record<Variant, string> = {
  primary: "bg-forest text-on-forest hover:opacity-90",
  secondary: "border border-line bg-card text-ink hover:border-forest",
  danger: "bg-danger text-paper hover:opacity-90",
  ghost: "text-muted hover:text-ink",
};

const base =
  "inline-flex items-center justify-center gap-2 rounded-full px-4 py-2 text-sm font-medium transition disabled:cursor-not-allowed disabled:opacity-40 disabled:saturate-0";

export function Button({ variant = "primary", className, ...props }: ComponentProps<"button"> & { variant?: Variant }) {
  return <button className={cx(base, variants[variant], className)} {...props} />;
}

export function ButtonLink({ variant = "primary", className, ...props }: ComponentProps<typeof Link> & { variant?: Variant }) {
  return <Link className={cx(base, variants[variant], className)} {...props} />;
}

type Tone = "forest" | "brass" | "danger" | "warn" | "muted";

const tones: Record<Tone, string> = {
  forest: "bg-forest-soft text-forest",
  brass: "bg-brass-soft text-brass",
  danger: "bg-danger-soft text-danger",
  warn: "bg-warn-soft text-warn",
  muted: "bg-paper text-muted border border-line",
};

export function Pill({ tone = "muted", children }: { tone?: Tone; children: ReactNode }) {
  return (
    <span className={cx("inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-medium", tones[tone])}>
      {children}
    </span>
  );
}

export function Field({ label, hint, children }: { label: string; hint?: ReactNode; children: ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1 block text-xs font-medium text-muted">{label}</span>
      {children}
      {hint && <span className="mt-1 block text-xs text-muted">{hint}</span>}
    </label>
  );
}

export const inputClass =
  "w-full rounded-xl border border-line bg-paper px-3 py-2 text-sm text-ink outline-none transition focus:border-forest";

export function Notice({ tone = "warn", children }: { tone?: "warn" | "danger" | "forest"; children: ReactNode }) {
  const style = { warn: "bg-warn-soft text-warn", danger: "bg-danger-soft text-danger", forest: "bg-forest-soft text-forest" }[tone];
  return <div className={cx("rounded-xl px-4 py-3 text-sm", style)}>{children}</div>;
}

export { cx };
