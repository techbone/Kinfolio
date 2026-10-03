import Link from "next/link";

import { ConnectButton } from "./connect-button";
import { NetworkSwitcher } from "./network-switcher";

export function Header() {
  return (
    <>
      <header className="mx-auto flex w-full max-w-5xl items-center justify-between gap-4 px-4 py-5 sm:px-6">
        <Link href="/" className="flex items-center gap-2">
          <Mark />
          <span className="font-display text-xl tracking-tight">Kinfolio</span>
        </Link>
        <nav className="flex items-center gap-1 sm:gap-3">
          <div className="hidden sm:block">
            <NetworkSwitcher />
          </div>
          <Link href="/trusts" className="hidden rounded-full px-3 py-2 text-sm text-muted hover:text-ink sm:block">
            My trusts
          </Link>
          <Link href="/create" className="hidden rounded-full px-3 py-2 text-sm text-muted hover:text-ink sm:block">
            Create
          </Link>
          <ConnectButton />
        </nav>
      </header>
      <nav className="mx-auto -mt-2 mb-2 flex w-full max-w-5xl items-center gap-5 border-b border-line px-4 pb-3 text-sm text-muted sm:hidden">
        <Link href="/trusts" className="hover:text-ink">
          My trusts
        </Link>
        <Link href="/create" className="hover:text-ink">
          Create a trust
        </Link>
        <div className="ml-auto">
          <NetworkSwitcher />
        </div>
      </nav>
    </>
  );
}

/** A wax-seal style mark: a ring with a sprouting stem. */
export function Mark({ className = "size-7" }: { className?: string }) {
  return (
    <svg viewBox="0 0 32 32" className={className} aria-hidden>
      <circle cx="16" cy="16" r="14" fill="var(--forest)" />
      <circle cx="16" cy="16" r="10.5" fill="none" stroke="var(--on-forest)" strokeOpacity="0.35" />
      <path d="M16 23v-8" stroke="var(--on-forest)" strokeWidth="1.8" strokeLinecap="round" />
      <path d="M16 15c0-3 2-5 5-5 0 3-2 5-5 5Z" fill="var(--brass)" />
      <path d="M16 18c0-2.6-1.8-4.4-4.4-4.4 0 2.6 1.8 4.4 4.4 4.4Z" fill="var(--on-forest)" />
    </svg>
  );
}
