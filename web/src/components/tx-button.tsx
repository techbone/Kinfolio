"use client";

import { useEffect } from "react";
import type { Abi, ContractFunctionArgs, ContractFunctionName } from "viem";
import { useWaitForTransactionReceipt, useWriteContract } from "wagmi";

import { errorMessage, explorerUrl } from "@/lib/hooks";
import { Button } from "./ui";

type Call<abi extends Abi, fn extends ContractFunctionName<abi, "nonpayable">> = {
  address: `0x${string}`;
  abi: abi;
  functionName: fn;
  args?: ContractFunctionArgs<abi, "nonpayable", fn>;
};

/** One-click contract write with wallet → confirming → done states. */
export function TxButton<abi extends Abi, fn extends ContractFunctionName<abi, "nonpayable">>({
  call,
  label,
  variant = "primary",
  disabled,
  onConfirmed,
  className,
}: {
  call: Call<abi, fn>;
  label: string;
  variant?: "primary" | "secondary" | "danger";
  disabled?: boolean;
  onConfirmed?: () => void;
  className?: string;
}) {
  const write = useWriteContract();
  const receipt = useWaitForTransactionReceipt({ hash: write.data });

  useEffect(() => {
    if (receipt.isSuccess) onConfirmed?.();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [receipt.isSuccess]);

  const busy = write.isPending || receipt.isLoading;
  const failed = receipt.data?.status === "reverted";
  const error = write.error ?? receipt.error;

  return (
    <div className={className}>
      <Button
        variant={variant}
        disabled={disabled || busy}
        // The generic call shape is checked at the call site; wagmi's overloads can't infer it here.
        onClick={() => write.mutate(call as never)}
        className="w-full sm:w-auto"
      >
        {write.isPending ? "Confirm in wallet…" : receipt.isLoading ? "Confirming…" : label}
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
