"use client";

import { useEffect, useState } from "react";
import type { Abi, ContractFunctionArgs, ContractFunctionName } from "viem";
import { useConnection, usePublicClient, useWaitForTransactionReceipt, useWriteContract } from "wagmi";

import { errorMessage, explorerUrl } from "@/lib/hooks";
import { Button } from "./ui";

type Call<abi extends Abi, fn extends ContractFunctionName<abi, "nonpayable">> = {
  address: `0x${string}`;
  abi: abi;
  functionName: fn;
  args?: ContractFunctionArgs<abi, "nonpayable", fn>;
};

/** One-click contract write with wallet → confirming → done states.
 * `batch` sets an explicit 1.5x gas limit: collectAll/distributeAll isolate
 * per-asset failures with try/catch, so an under-padded wallet estimate would
 * make inner calls fail quietly instead of reverting. */
export function TxButton<abi extends Abi, fn extends ContractFunctionName<abi, "nonpayable">>({
  call,
  label,
  variant = "primary",
  disabled,
  onConfirmed,
  className,
  batch,
}: {
  call: Call<abi, fn>;
  label: string;
  variant?: "primary" | "secondary" | "danger";
  disabled?: boolean;
  onConfirmed?: () => void;
  className?: string;
  batch?: boolean;
}) {
  const { address: account } = useConnection();
  const client = usePublicClient();
  const write = useWriteContract();
  const receipt = useWaitForTransactionReceipt({ hash: write.data });

  // After a confirmed tx, hold the button for a few seconds so stale reads
  // can't invite a duplicate click before the page refreshes.
  const [cooling, setCooling] = useState(false);
  useEffect(() => {
    if (!receipt.isSuccess) return;
    onConfirmed?.();
    setCooling(true);
    const id = setTimeout(() => setCooling(false), 6000);
    return () => clearTimeout(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [receipt.isSuccess]);

  const busy = write.isPending || receipt.isLoading || cooling;

  async function send() {
    let gas: bigint | undefined;
    if (batch && client && account) {
      try {
        gas = ((await client.estimateContractGas({ ...call, account } as never)) * 3n) / 2n;
      } catch {
        // let the wallet estimate and surface the revert reason itself
      }
    }
    // The generic call shape is checked at the call site; wagmi's overloads can't infer it here.
    write.mutate({ ...call, gas } as never);
  }
  const failed = receipt.data?.status === "reverted";
  const error = write.error ?? receipt.error;

  return (
    <div className={className}>
      <Button
        variant={variant}
        disabled={disabled || busy}
        onClick={() => void send()}
        className="w-full sm:w-auto"
      >
        {write.isPending
          ? "Confirm in wallet…"
          : receipt.isLoading
            ? "Confirming…"
            : cooling
              ? "Done ✓"
              : label}
      </Button>
      {write.data && (
        <a
          href={explorerUrl("tx", write.data)}
          target="_blank"
          rel="noreferrer"
          className="mt-1 block text-xs text-muted underline-offset-2 hover:underline"
        >
          {receipt.isSuccess && !failed ? "Confirmed ↗" : failed ? "Reverted ↗" : "View transaction ↗"}
        </a>
      )}
      {error && !write.isPending && (
        <p className="mt-1 max-w-xs text-xs text-danger">{errorMessage(error)}</p>
      )}
    </div>
  );
}
