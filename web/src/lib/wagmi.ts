import { createConfig, fallback, http, injected } from "wagmi";
import { robinhood, robinhoodTestnet } from "viem/chains";

// The public RPCs occasionally drop connections, so every read retries and an
// optional private endpoint (e.g. Alchemy) is tried first when configured.
function transport(...urls: (string | undefined)[]) {
  return fallback(
    urls
      .filter((url): url is string => Boolean(url))
      .map((url) => http(url, { retryCount: 4, retryDelay: 400 })),
  );
}

export const wagmiConfig = createConfig({
  // First chain is the default: the testnet demo, where timers run in minutes.
  chains: [robinhoodTestnet, robinhood],
  // EIP-6963 discovers desktop extensions (MetaMask, Rabby…); this generic
  // connector covers mobile in-app wallet browsers that only expose window.ethereum.
  connectors: [injected()],
  transports: {
    [robinhoodTestnet.id]: transport(process.env.NEXT_PUBLIC_RPC_TESTNET, "https://rpc.testnet.chain.robinhood.com"),
    [robinhood.id]: transport(process.env.NEXT_PUBLIC_RPC_MAINNET, "https://rpc.mainnet.chain.robinhood.com"),
  },
  ssr: true,
});

export type ChainId = (typeof wagmiConfig.chains)[number]["id"];

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig;
  }
}
