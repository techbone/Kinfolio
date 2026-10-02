import { createConfig, fallback, http, injected } from "wagmi";
import { robinhoodTestnet } from "viem/chains";

// The public RPC occasionally drops connections, so every read retries and an
// optional private endpoint (e.g. Alchemy) is tried first when configured.
const testnetRpcs = [
  process.env.NEXT_PUBLIC_RPC_TESTNET,
  "https://rpc.testnet.chain.robinhood.com",
].filter((url): url is string => Boolean(url));

export const wagmiConfig = createConfig({
  chains: [robinhoodTestnet],
  // EIP-6963 discovers desktop extensions (MetaMask, Rabby…); this generic
  // connector covers mobile in-app wallet browsers that only expose window.ethereum.
  connectors: [injected()],
  transports: {
    [robinhoodTestnet.id]: fallback(
      testnetRpcs.map((url) => http(url, { retryCount: 4, retryDelay: 400 })),
    ),
  },
  ssr: true,
});

export type ChainId = (typeof wagmiConfig.chains)[number]["id"];

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig;
  }
}
