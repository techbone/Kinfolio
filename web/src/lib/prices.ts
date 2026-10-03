"use client";

import { useReadContracts } from "wagmi";

import type { Token } from "./config";
import type { ChainId } from "./wagmi";

const aggregatorAbi = [
  {
    type: "function",
    name: "latestRoundData",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "roundId", type: "uint80" },
      { name: "answer", type: "int256" },
      { name: "startedAt", type: "uint256" },
      { name: "updatedAt", type: "uint256" },
      { name: "answeredInRound", type: "uint80" },
    ],
  },
] as const;

/** USD price per token: live Chainlink on mainnet, labelled demo prices on testnet. */
export function usePrices(chainId: ChainId, tokens: Token[]) {
  const withFeed = tokens.filter((t) => t.feed);
  const feeds = useReadContracts({
    contracts: withFeed.map((t) => ({
      address: t.feed!,
      abi: aggregatorAbi,
      functionName: "latestRoundData" as const,
      chainId,
    })),
    query: { enabled: withFeed.length > 0, refetchInterval: 60_000 },
  });

  const live = new Map<string, number>();
  withFeed.forEach((t, i) => {
    const answer = feeds.data?.[i]?.result?.[1];
    if (answer !== undefined && answer > 0n) live.set(t.address.toLowerCase(), Number(answer) / 1e8);
  });

  return {
    source: withFeed.length > 0 ? ("chainlink" as const) : ("demo" as const),
    price: (token: Token) => live.get(token.address.toLowerCase()) ?? (token.feed ? 0 : token.demoPrice),
  };
}
