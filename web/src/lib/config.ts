import type { Address } from "viem";
import { robinhood, robinhoodTestnet } from "viem/chains";

export type Token = {
  address: Address;
  symbol: string;
  name: string;
  decimals: number;
  kind: "stock" | "cash";
  /** Chainlink USD feed (8 decimals). Prices one token, multiplier included. */
  feed?: Address;
  /** Fallback valuation where no feed exists (testnet has no Chainlink). */
  demoPrice: number;
};

export type Deployment = {
  chainId: number;
  label: string;
  explorer: string;
  factory: Address;
  implementation: Address;
  profile: "demo" | "production";
  tokens: Token[];
};

const FACTORY: Address = "0xbdEF1e8cb7DB12a81d6C32f5E57D2ccE41b4A90F";
const IMPLEMENTATION: Address = "0x821D8133adfd1fc9aE2e90195C5Ac0E4bdbEdaD7";

export const deployments: Record<number, Deployment> = {
  [robinhood.id]: {
    chainId: robinhood.id,
    label: "Mainnet",
    explorer: "https://robinhoodchain.blockscout.com",
    factory: FACTORY,
    implementation: IMPLEMENTATION,
    profile: "production",
    // From Robinhood's asset registry (api.robinhood.com/rhj/assets) and
    // Chainlink's Robinhood Chain feed directory.
    tokens: [
      stock("0x322F0929c4625eD5bAd873c95208D54E1c003b2d", "TSLA", "Tesla", "0x4A1166a659A55625345e9515b32adECea5547C38"),
      stock("0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC", "NVDA", "NVIDIA", "0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15"),
      stock("0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9", "AAPL", "Apple", "0x6B22A786bAa607d76728168703a39Ea9C99f2cD0"),
      stock("0xe93237C50D904957Cf27E7B1133b510C669c2e74", "MSFT", "Microsoft", "0x45C3C877C15E6BA2EBB19eA114Ea508d14C1Af2E"),
      stock("0x12f190a9F9d7D37a250758b26824B97CE941bF54", "AMZN", "Amazon", "0xD5a1508ceD74c084eBf3cBe853e2C968fB2a651C"),
      stock("0x2e0847E8910a9732eB3fb1bb4b70a580ADAD4FE3", "GOOGL", "Alphabet", "0xF6f373a037c30F0e5010d854385cA89185AE638b"),
      stock("0xc0D6457C16Cc70d6790Dd43521C899C87ce02f35", "META", "Meta", "0x7C38C00C30BEe9378381E7B6135d7283356D71b1"),
      stock("0x894E1EC2D74FFE5AEF8Dc8A9e84686acCB964F2A", "PLTR", "Palantir", "0x820ABedFF239034956B7A9d2F0a331f9F075eB4c"),
      stock("0x86923f96303D656E4aa86D9d42D1e57ad2023fdC", "AMD", "AMD", "0x943A29E7ae51A4798823ca9eEd2ed533B2A22C72"),
      stock("0x6330D8C3178a418788dF01a47479c0ce7CCF450b", "COIN", "Coinbase", "0xA3a468A452940B7D6b69991207B508c609a98Ef2"),
      stock("0x117cc2133c37B721F49dE2A7a74833232B3B4C0C", "SPY", "S&P 500 ETF", "0x319724394D3A0e3669269846abE664Cd621f9f6A"),
      stock("0xD5f3879160bc7c32ebb4dC785F8a4F505888de68", "QQQ", "Nasdaq-100 ETF", "0x80901d846d5D7B030F26B480776EE3b29374C2ae"),
      cash("0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168", "0x61B7e5650328764B076A108EFF5fa7282a1B9aD2"),
    ],
  },
  [robinhoodTestnet.id]: {
    chainId: robinhoodTestnet.id,
    label: "Testnet",
    explorer: "https://explorer.testnet.chain.robinhood.com",
    factory: FACTORY,
    implementation: IMPLEMENTATION,
    profile: "demo",
    tokens: [
      stock("0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E", "TSLA", "Tesla", undefined, 430),
      stock("0x5884aD2f920c162CFBbACc88C9C51AA75eC09E02", "AMZN", "Amazon", undefined, 225),
      stock("0x3b8262A63d25f0477c4DDE23F83cfe22Cb768C93", "NFLX", "Netflix", undefined, 1210),
      stock("0x1FBE1a0e43594b3455993B5dE5Fd0A7A266298d0", "PLTR", "Palantir", undefined, 180),
      stock("0x71178BAc73cBeb415514eB542a8995b82669778d", "AMD", "AMD", undefined, 165),
      cash("0x7E955252E15c84f5768B83c41a71F9eba181802F"),
    ],
  },
};

/** Testnet is the default so anyone can try the full lifecycle in minutes. */
export const defaultChain = robinhoodTestnet;
export const supportedChains = [robinhood, robinhoodTestnet] as const;

export function getDeployment(chainId: number | undefined): Deployment | undefined {
  return chainId === undefined ? undefined : deployments[chainId];
}

export function tokenOf(chainId: number | undefined, address: string): Token | undefined {
  return getDeployment(chainId)?.tokens.find((t) => t.address.toLowerCase() === address.toLowerCase());
}

export function explorerUrl(chainId: number | undefined, kind: "tx" | "address", value: string): string {
  const base = getDeployment(chainId)?.explorer ?? deployments[defaultChain.id].explorer;
  return `${base}/${kind}/${value}`;
}

function stock(address: Address, symbol: string, name: string, feed?: Address, demoPrice = 0): Token {
  return { address, symbol, name, decimals: 18, kind: "stock", feed, demoPrice };
}

function cash(address: Address, feed?: Address): Token {
  return { address, symbol: "USDG", name: "Global Dollar", decimals: 6, kind: "cash", feed, demoPrice: 1 };
}
