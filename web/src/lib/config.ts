import type { Address } from "viem";
import { robinhoodTestnet } from "viem/chains";

export type Token = {
  address: Address;
  symbol: string;
  name: string;
  decimals: number;
  kind: "stock" | "cash";
  /** Demo valuation for testnet, which has no Chainlink feeds. */
  demoPrice: number;
};

export type Deployment = {
  factory: Address;
  implementation: Address;
  profile: "demo" | "production";
  tokens: Token[];
};

export const deployments: Record<number, Deployment> = {
  [robinhoodTestnet.id]: {
    factory: "0xbdEF1e8cb7DB12a81d6C32f5E57D2ccE41b4A90F",
    implementation: "0x821D8133adfd1fc9aE2e90195C5Ac0E4bdbEdaD7",
    profile: "demo",
    tokens: [
      stock("0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E", "TSLA", "Tesla", 430),
      stock("0x5884aD2f920c162CFBbACc88C9C51AA75eC09E02", "AMZN", "Amazon", 225),
      stock("0x3b8262A63d25f0477c4DDE23F83cfe22Cb768C93", "NFLX", "Netflix", 1210),
      stock("0x1FBE1a0e43594b3455993B5dE5Fd0A7A266298d0", "PLTR", "Palantir", 180),
      stock("0x71178BAc73cBeb415514eB542a8995b82669778d", "AMD", "AMD", 165),
      {
        address: "0x7E955252E15c84f5768B83c41a71F9eba181802F",
        symbol: "USDG",
        name: "Global Dollar",
        decimals: 6,
        kind: "cash",
        demoPrice: 1,
      },
    ],
  },
};

export const defaultChain = robinhoodTestnet;

export function getDeployment(chainId: number | undefined): Deployment | undefined {
  return chainId === undefined ? undefined : deployments[chainId];
}

export function tokenOf(chainId: number | undefined, address: string): Token | undefined {
  return getDeployment(chainId)?.tokens.find(
    (t) => t.address.toLowerCase() === address.toLowerCase(),
  );
}

function stock(address: Address, symbol: string, name: string, demoPrice: number): Token {
  return { address, symbol, name, decimals: 18, kind: "stock", demoPrice };
}
