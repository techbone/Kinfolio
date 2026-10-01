import type { Metadata } from "next";
import { Fraunces, Inter, JetBrains_Mono } from "next/font/google";

import { Header } from "@/components/header";
import { Providers } from "@/components/providers";
import "./globals.css";

const fraunces = Fraunces({ subsets: ["latin"], variable: "--font-fraunces" });
const inter = Inter({ subsets: ["latin"], variable: "--font-inter" });
const mono = JetBrains_Mono({ subsets: ["latin"], variable: "--font-mono" });

export const metadata: Metadata = {
  title: "Kinfolio — a family trust for your stock tokens",
  description:
    "Name heirs for your Robinhood Chain stock tokens and USDG with trust rules: tranches, ages and allowances. No escrow, no lawyer, no admin keys.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${fraunces.variable} ${inter.variable} ${mono.variable}`}>
      <body className="min-h-screen">
        <Providers>
          <Header />
          <main className="mx-auto w-full max-w-5xl px-4 pb-24 sm:px-6">{children}</main>
        </Providers>
      </body>
    </html>
  );
}
