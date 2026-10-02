# Kinfolio Security

This document covers what Kinfolio guarantees, how each guarantee is enforced and tested, what we considered an attacker could do, and what remains a known risk.

> **Status:** unaudited buildathon code. Do not use it with funds you cannot afford to lose.

---

## 1. Trust model

| Property | How it holds |
|---|---|
| **No escrow** | The owner keeps their tokens. A trust only holds an ERC-20 allowance, and the single `transferFrom` in the codebase is gated by `state == Released`. |
| **One contract per family** | Every trust is an EIP-1167 clone with its own address. Approvals are granted to *that* clone, so no trust can spend another family's allowance. A shared-approval "confused deputy" isn't possible by construction. |
| **Zero admin** | No owner, pauser, upgrader or fee switch on `KinfolioFactory` or `KinfolioTrust`. The deployer has no power after deployment. Timing minimums are immutables fixed per deployment. |
| **Destinations are stored, never supplied** | Tokens move only `owner → trust` (collect) and `trust → grant.beneficiary` (distribute). No function takes a recipient for funds, except `transferGrant`, which only the current beneficiary can call. |
| **Permissionless completion** | `finalize`, `collect`, `collectAll`, `distribute` and `distributeAll` are callable by anyone. Heirs never depend on Kinfolio's web app or on any server. |
| **No oracle on the money path** | Settlement depends only on balances and `block.timestamp`. Prices are display-only. |

## 2. Invariants and their proofs

Each invariant is enforced in code and exercised by tests. The invariant suite drives a trust through random sequences of the following:
- owner trades, buys and approvals
- time jumps
- claims, vetoes, settlement, collection and payouts
- stranger actions
- issuer pauses

The run is 256 runs × 64 calls, and the invariants are checked after every call.

| ID | Invariant | Enforced by | Tested by |
|---|---|---|---|
| I1 | Nothing is pulled from the owner before release | `collect` is `inState(Released)` | `invariant_OwnerFundsMoveOnlyAfterRelease`, `test_RevertWhen_CollectingBeforeRelease` |
| I2 | `transferFrom` only ever moves `owner → trust` | `from` is read from storage and `to` is `address(this)` | `invariant_OwnerFundsMoveOnlyAfterRelease`: owner balance + collected always equals what the owner's own trades leave |
| I3 | Tokens leave the trust only to a stored beneficiary, or to the owner via `rescue` while nothing has been collected | `distribute` reads `grant.beneficiary`; `rescue` is limited to Active/Closed | `invariant_TrustIsExactlySolvent` (heirs hold exactly what was distributed), `test_Distribute_PaysStoredBeneficiaryWhoeverCalls`, `test_RevertWhen_RescuingAfterRelease` |
| I4 | For every asset, `Σ distributed ≤ collected`, and trust balance `= collected − Σ distributed` | Balance-delta accounting, checks-effects-interactions | `invariant_TrustIsExactlySolvent`, `test_FullSettlementAccountsForEveryToken` |
| I5 | No grant is ever paid more than it has vested | `claimable = vested − distributed`, floored at 0 | `invariant_PayoutsWithinVestedEntitlement`, plus 5 fuzzed properties of `Vesting.vested` × 1,000 runs (bounded, monotonic in time and amount) |
| I6 | Only an owner signature returns Challenge → Active; only elapsed time reaches Released | `checkIn` is `onlyOwner`; strict `>` deadlines | `invariant_NoIllegalTransitions`, `test_StartClaim_BoundaryIsStrict`, `test_Finalize_BoundaryIsStrict`, `test_RevertWhen_StrangerStartsClaim` |
| I7 | No privileged role exists | No such functions; the implementation's initializers are disabled; only the factory can initialize a clone | `test_RevertWhen_InitializingImplementation`, `test_RevertWhen_CloneInitializedByNonFactory`, `test_RevertWhen_NonTrustWritesIndex` |

## 3. Threat model

The attack tree was carried over from our earlier inheritance-vault work (AfterKey) and extended for allowances and stock tokens.

### G1: Take assets while the owner is alive
| Path | Mitigation |
|---|---|
| Use the trust's allowance early | I1. `collect` requires Released, which requires inactivity **and** an unvetoed challenge window. |
| Use trust A's allowance via trust B | Impossible: allowances are per clone (§1). |
| Strangers move the state machine | `startClaim` requires being a beneficiary; `checkIn` requires the owner (I6). |
| Re-initialize a clone or the implementation | `initializer` plus factory-only init, and the implementation is locked at deployment (I7). |
| Reentrancy through a malicious covered token | `nonReentrant` on every token-moving function, plus checks-effects-interactions. Batch loops call the guarded single-asset functions. |
| Malicious upgrade | No proxy admin and no upgrade path: clones point at an immutable implementation. |
| Compromised owner key rewrites the grants | **Accepted:** equivalent to a compromised wallet. Roadmap: a grant-change timelock and alerts. |

### G2: Redirect an inheritance
| Path | Mitigation |
|---|---|
| Phish an heir into signing `distribute` | Harmless: the destination is the stored beneficiary, whoever calls. |
| Front-run payout with a substituted recipient | Not possible: there is no recipient argument. |
| Steal an heir's grant | `transferGrant` only works when called by the current beneficiary, and only after release (`test_RevertWhen_TransferGrantMisused`). |

### G3: Block or delay an inheritance
| Path | Mitigation |
|---|---|
| Issuer pauses one stock token | `collectAll` and `distributeAll` isolate each asset with `try this.collect(...)`. A paused ticker emits `CollectFailed`/`DistributeFailed` and can be retried; the rest settle (`test_CollectAll_IsolatesPausedAsset`, `test_DistributeAll_IsolatesPausedAsset`). |
| Issuer burns from the owner (`adminBurn`) | The trust collects whatever remains (`test_Collect_AfterIssuerBurnTakesWhatRemains`). |
| Kinfolio disappears | Every completion step is permissionless and callable from any block explorer. |
| A stranger vetoes | Impossible; only the owner can (I6). |
| The owner sells or moves assets after setup | By design, coverage follows the wallet, like a transfer-on-death account (`test_Collect_FollowsOwnerTradingWhileAlive`). |

### G4: Grief the owner
| Path | Mitigation |
|---|---|
| Premature claim spam by an heir | Only possible after the owner is already silent past the deadline. A veto is one transaction and resets the clock. |
| Edits during a claim | Configuration is frozen outside Active (`test_RevertWhen_EditingDuringChallenge`). The owner must veto first, which is itself proof of life. |
| Tokens sent to the trust by mistake | The owner can `rescue` them while Active or Closed. That is never possible once a claim has started. |

### G5: Systemic risks
| Path | Mitigation |
|---|---|
| False release, where the owner is alive but ignores the deadline *and* the whole window | Conservative production minimums: **30 days** inactivity and **7 days** challenge, fixed in the mainnet implementation. |
| Lookalike front-end | Contracts are verified, and the README lists the canonical factory address for both chains. |

## 4. Stock-token specifics

Robinhood Chain stock tokens are OpenZeppelin ERC-20s behind beacon proxies. We checked the live implementation before designing around it:
- Standard `approve`/`transferFrom` and EIP-2612 `permit`.
- Transfers to EOAs and to contracts both succeed.
- An issuer `pause()` and `adminBurn()`.
- The ERC-8056 functions `uiMultiplier()`, `newUIMultiplier()`, `effectiveAt()` and `balanceOfUI()`.

How Kinfolio handles them:

- **Raw-unit accounting.** All entitlements are in raw token units. Splits and reinvested dividends change `uiMultiplier`, not balances, so a locked tranche keeps its full share count through corporate actions with no code path involved (`test_SplitDuringLockupReachesHeirInFull`).
- **Balance-delta collection.** `collected` is the trust's measured balance change, not the requested amount, so non-standard tokens can't inflate entitlements (`test_Collect_CountsBalanceDeltaNotRequestedAmount`).
- **Live verification.** `test_Fork_FullLifecycleWithRealStockTokens` runs the full lifecycle against the real testnet TSLA, AMZN and USDG contracts.

## 5. Testing methodology

| Suite | Tests | What it covers |
|---|---|---|
| `KinfolioTrust.Lifecycle.t.sol` | 31 | State machine, access control, strict timing boundaries, every config validation, close and rescue |
| `KinfolioTrust.Settlement.t.sol` | 25 | Collect, distribute, tranches, linear vesting, cash sleeve, issuer pause and burn, fee-on-transfer, ERC-8056 split, heir wallet rotation |
| `KinfolioFactory.t.sol` | 12 | Deterministic addresses, salt scoping, index, initializer lockdown, deployment profiles |
| `Vesting.t.sol` | 7 | 5 fuzzed properties × 1,000 runs, plus edge cases |
| `invariant/KinfolioInvariant.t.sol` | 5 invariants | 256 runs × 64 random calls each |
| `fork/RobinhoodTestnet.t.sol` | 1 | Live Robinhood Chain testnet tokens |

**Coverage:** 99.6% of lines, 99.7% of statements, 97.9% of branches and 100% of functions in `src/`. The one line reported as uncovered is the constructor's invalid-profile revert. `test_RevertWhen_ImplementationDeployedWithBadProfile` exercises it, but Foundry doesn't attribute constructor reverts.

**Proving the invariants actually run.** An invariant that never reaches settlement passes vacuously. We measured reachability with `show_metrics` by making no-op handler calls revert on purpose. That revealed the first handler version reached release in only 11 of 256 runs, with zero real payouts. After adding a fast-forward action, about 249 of 256 runs reach release, with hundreds of successful collections and payouts per campaign.

**A real finding from the fuzzer.** The invariant suite once reported "paid beyond vested". The cause was in the test harness, not the contract: a handler called `vm.warp` to a past deadline inside a call that then reverted. Cheatcode time changes survive reverts, so time ran backwards. The handler now only ever warps forward (`_warpPast`). Real chains never rewind time.

## 6. Static analysis

`forge build` produces no warnings and `forge lint` reports no findings. Four lints are excluded project-wide in `contracts/foundry.toml`, deliberately:

| Lint | Why it is excluded |
|---|---|
| `block-timestamp` | Time *is* the product: inactivity, challenge and vesting are measured in days to years, so seconds of sequencer drift are irrelevant. |
| `require-revert-in-loop` | Config validation must reject the whole input, not skip bad entries. |
| `calls-loop` | Loops are bounded (16 assets × 12 grants), and every per-asset call is isolated by try/catch so one failure can't block the rest. |
| `reentrancy-events` | Every token-moving function is `nonReentrant`. The only other external callee is the immutable factory. |

One inline disable remains: `arbitrary-send-erc20` on the single `safeTransferFrom`. Its `from` is always the stored owner and the call is reachable only after release (I1, I2).

## 7. Known limitations

- **Unaudited.**
- **No keeper or notifications yet.** Someone has to send the settle and payout transactions, and owners get no reminder emails. Both are on the roadmap; the contracts already allow any keeper to do it.
- **Owner-key compromise** lets an attacker edit grants. That is the same exposure as a compromised wallet. A grant-change timelock is on the roadmap.
- **The factory's heir index is append-only.** Readers must confirm current grants on the trust; the web app does.
- **Rounding dust.** At most one wei per grant per asset stays in the trust.
- **Tokens sent directly to a released trust** are not attributed to heirs.
- **Covered assets must be chosen by the owner.** A malicious token the owner adds can only grief its own collection, never other assets.
