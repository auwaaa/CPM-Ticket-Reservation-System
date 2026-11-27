# M2 Report Section — Participants (`Seller` & `Buyer`) and System Assumptions

**Author:** Pham Khac Uy (M2, `10423122`) · **Branch:** `feat/participants`  
**Specification:** [Revised Project Proposal](revised_project_proposal.md), Sections 4–7  
**Role Contract:** [Role Execution Plan](temp_role_execution_plan.md), Section 4  
**Models:** [`models/defs.pml`](../models/defs.pml), [`models/02_final.pml`](../models/02_final.pml), [`models/01_naive.pml`](../models/01_naive.pml)

---

## 1. Participant Processes Overview

The Ticket Reservation System models two participant roles interacting asynchronously with the central `Marketplace` over bounded FIFO channels (`mkt_req`, `seller_ch`, and `buyer_ch[N]`):

* **1 `Seller()` process** (representing the ticket owner, `SELLER_ID = 0` on `mkt_req`).
* **`N` `Buyer(byte id)` processes** (`id ∈ {0, ..., N - 1}`, base configuration `N = 2`, scaled up to `N = 4` in the scalability study).

Both `models/01_naive.pml` and `models/02_final.pml` execute the **exact same `Seller()` and `Buyer(byte id)` implementations**, ensuring that every counterexample discovered in `01_naive.pml` stems purely from defects in `Marketplace` or `PaymentService` rather than differences in participant behaviour.

---

## 2. Behavioral Design & Requirements Mapping

### 2.1 `Seller()` Contract

The `Seller()` process (`models/02_final.pml`, `end_seller:`) models the two points where the seller acts independently and can either cooperate or fail/withdraw:

| Action / Choice | Guard | Message & Reply | FR Mapping | Concurrency Hazard Exercised |
| :--- | :--- | :--- | :--- | :--- |
| **Withdraw listing** | `ticket_state == AVAILABLE && !withdraw_tried` | `mkt_req ! withdraw(SELLER_ID, NO_RES); seller_ch ? reply` | FR-3, FR-5 | Races with concurrent `Buyer` `reserve` requests in `AVAILABLE`. |
| **Report delivery** | `ticket_state == PAID && !deliver_decided` | `mkt_req ! deliver(SELLER_ID, NO_RES); seller_ch ? reply` | FR-3, FR-10(a) | Races with `Marketplace` `delivery_timeout`; if timeout wins, `deliver` receives `deliver_fail`. |
| **Non-delivery fault** | `ticket_state == PAID && !deliver_decided` | `skip` (no message sent) | FR-10(b), L2 | Simulates an unresponsive/defaulting seller, forcing `delivery_timeout` to move `PAID -> REFUNDED`. |

* **Single-decision flags (`withdraw_tried`, `deliver_decided`):** Bound each non-deterministic seller decision to at most once per run, preventing infinite retry stuttering loops that would break weak-fairness liveness verification (`L1`–`L5`).

### 2.2 `Buyer(byte id)` Contract

Each `Buyer(byte id)` (`models/02_final.pml`, `end_buyer:`) maintains a unique identifier `id ∈ [0, N - 1]`, an attempt counter `attempts` (bounded by `K = 2`), and its latest granted reservation identifier `my_res`:

| Action / Choice | Guard | Message & Reply | FR Mapping | Concurrency Hazard Exercised |
| :--- | :--- | :--- | :--- | :--- |
| **Reserve attempt** | `attempts < K && ticket_state == AVAILABLE` | `mkt_req ! reserve(id, NO_RES); buyer_ch[id] ? reply, tmp_r` | FR-3, FR-4, FR-6, FR-12 | Multiple buyers race to reserve; `Marketplace` auto-charges on `reserve_ok` (no separate `pay` command). |
| **Pre-`PAID` cancel** | Inside `reserve_ok` branch | `mkt_req ! cancel(id, my_res); buyer_ch[id] ? reply, tmp_r` | FR-8(b) | Races with in-flight `charge_ok` / `charge_fail` from `PaymentService` and `res_timeout`. |
| **Pre-`PAID` silence / abandon** | Inside `reserve_ok` branch | `skip` (do not cancel) | FR-6, FR-8(a), FR-8(c) | Lets `charge_ok`, `charge_fail`, or `res_timeout` resolve `RESERVED`. If `res_timeout` fires, the buyer can retry (`attempts < K`), exercising the ABA scenario. |
| **Explicit delivery confirmation** | `ticket_state == DELIVERED && current_buyer == id && !confirm_decided` | `mkt_req ! confirm(id, my_res); buyer_ch[id] ? reply, tmp_r` | FR-3, FR-11(a), S5 | Normal settlement path (`DELIVERED -> SETTLED`, triggers `payout`). |
| **Silent confirmation (window expiry)** | `ticket_state == DELIVERED && current_buyer == id && !confirm_decided` | `skip` (stay silent) | FR-11(b), Assumption 6 | Simulates a buyer who stops responding after receiving the ticket; `Marketplace` `confirm_timeout` auto-confirms (`DELIVERED -> SETTLED`). |
| **Unauthorized / spoofed request** | `!spoofed && current_buyer != id && current_buyer != NO_BUYER && !is_terminal` | `mkt_req ! cancel(id, 1)` or `confirm(id, 1); buyer_ch[id] ? reply, tmp_r` | FR-3, FR-8, FR-11 | Tests authorization checks in `Marketplace`: `02_final.pml` must reject with `*_fail`; `01_naive.pml` accepts `confirm` in `PAID`, exposing `S5`. |

---

## 3. System Assumptions & Design Rationale (Assumptions 1–7)

To keep the PROMELA model faithful to the revised specification while remaining exhaustively verifiable in SPIN, the participant layer relies on the seven system assumptions defined in [Section 7 of the Revised Proposal](revised_project_proposal.md):

| # | Assumption | How M2 & the Model Enforce / Depend on It |
| :-: | :--- | :--- |
| **1** | **Bounded lossless FIFO channels** | `mkt_req` (`[4]`), `buyer_ch[N]` (`[2]`), `seller_ch` (`[2]`), `pay_req` (`[2]`), `pay_resp` (`[2]`) never drop, duplicate, or reorder messages. Strict 1-to-1 request/reply pairing (`FR-3`) prevents reply queue overflow. |
| **2** | **Restricted failure scope** | Only modeled faults occur: payment gateway declines (`charge_fail`), buyer cancellation/abandonment, seller withdrawal, and seller non-delivery. |
| **3** | **Marketplace atomicity** | `Marketplace` handles one command, payment reply, or timeout to completion inside `atomic`/`d_step`, while participants interleave freely between sending a request and receiving its reply. |
| **4** | **Eventual payment response** | Every `charge(b, r)` produces either `charge_ok` or `charge_fail`. Hence a silent buyer in `RESERVED` (`skip`) never hangs `Marketplace` indefinitely. |
| **5** | **Fixed scope & no post-`PAID` buyer cancel** | Ticket price is fixed at `1` unit; any stale/spoofed `cancel` after `PAID` is rejected by `Marketplace` (`FR-3`/`FR-8`). |
| **6** | **Finite abstract timeouts** | `res_timeout` (`RESERVED -> AVAILABLE`), `delivery_timeout` (`PAID -> REFUNDED`), and `confirm_timeout` (`DELIVERED -> SETTLED`) guarantee liveness (`L1`, `L2`, `L5`) even when `Buyer` or `Seller` picks the silent `skip` branch. |
| **7** | **Atomic integer ledger & `INIT_BAL = K`** | Each buyer starts with `balance[id] = INIT_BAL = K` (`B0 = N * K`), guaranteeing a buyer can always fund up to `K` legitimate reservation attempts (including when a late `charge_ok` from attempt 1 is still temporarily held in `escrow` while attempt 2 begins). |

### 3.1 Why Bounded Retries `K = 2` (FR-12)?

1. **Finite-state requirement:** Unbounded buyer retries (`while (true)`) with monotonically increasing `next_res_id` would produce an infinite state space (overflowing `byte` reservation IDs and `MAX_RES_ID`), making exhaustive SPIN model checking impossible.
2. **Why `K = 2` specifically (not `K = 1`):** Setting `K = 1` prevents any buyer from ever re-attempting a reservation after `res_timeout` or `cancel`. Setting `K = 2` is the **minimal bound that exposes the ABA stale-charge race** (Buyer `b` reserves `r = 1`, `res_timeout` releases the ticket to `AVAILABLE`, Buyer `b` reserves again `r = 2`, and the delayed `charge_ok(b, 1)` arrives). As confirmed in `models/01_naive.pml`, `K = 2` is sufficient to trigger both `01_naive_S4.trail` (ABA stale charge) and `01_naive_S1.trail` (double sale).

### 3.2 Reconciling `confirm(b, r)` and `confirm_timeout` (FR-11 & S5)

During requirements review, a consistency gap was identified between allowing payout after confirmation window expiry and requiring *"paid only after delivery is confirmed"* (`S5`). The revised model resolves this cleanly at both the specification and participant levels:

* In `DELIVERED`, `Buyer(id)` non-deterministically chooses **either** explicit `confirm(id, my_res)` **or** silence (`skip`).
* Both explicit `confirm(b, r)` (`FR-11(a)`) and `confirm_timeout` (`FR-11(b)`, implicit confirmation) set `deliveryConfirmed = true` before `Marketplace` transitions to `SETTLED` and dispatches `payout`.
* Thus, `Seller` cannot be starved indefinitely by an inactive buyer (`L5`), while `S5` (`seller_bal > 0 -> (ever_delivered && deliveryConfirmed && ticket_state == SETTLED)`) holds across every interleaving.

---

## 4. State-Space Engineering in `Seller()` and `Buyer(byte id)`

Because `N` buyers and `Seller` share guards over global state (`ticket_state`, `current_buyer`), naive participant structure easily triggers state-space explosion. Three structural rules in M2 keep `N = 2, K = 2` tractable (documented quantitatively in [`m3_ltl_and_counterexamples.md`](m3_ltl_and_counterexamples.md), Section 7):

1. **Atomic `"decide → send → await reply"` steps:** Each participant command and its immediate reply read (`buyer_ch[id] ? reply, tmp_r` or `seller_ch ? reply`) are wrapped in `atomic { ... }`. Whenever the reply channel is empty, PROMELA automatically suspends atomicity at the blocking receive so `Marketplace` and `PaymentService` can run, while eliminating meaningless internal interleavings before the send and after the receive (e.g., clearing `reply = 0; tmp_r = 0` inside the same block).
2. **Pre-filtering futile requests without suppressing real races:**
   * `Buyer` checks `ticket_state == AVAILABLE` before entering its `reserve` block. Because `Marketplace` processes `mkt_req` asynchronously, **both buyers (and `Seller` withdrawing) can still observe `AVAILABLE` concurrently and enqueue competing commands**, preserving all `FR-4` and `FR-5` races while pruning blind reserve spam in `PAID`/`DELIVERED`/terminal states.
   * `Buyer` restricts its `spoofed` attempt to `!spoofed && current_buyer != id && current_buyer != NO_BUYER && !is_terminal`—the only window where an unauthorized request can threaten safety (`S5` in `01_naive.pml`).
3. **Idle termination at `end_seller:` / `end_buyer:` (no `is_terminal -> break`):** Rather than adding an explicit `:: is_terminal -> break` branch, every guard in `Seller()` and `Buyer(byte id)` becomes false once the listing reaches a terminal state (`SETTLED`, `WITHDRAWN`, `REFUNDED`). All participants block cleanly at their `end_*` labels (valid end states in SPIN), avoiding $(N + 1)!$ irrelevant exit-order permutations. Together with M1/M3 optimizations, this reduced the `N = 2, K = 2` state space from **19,976,231 to 12,427,383 stored states** (and `K = 1` from **298,241 to 164,029 states**).

---

## 5. M2 Acceptance Criteria Sign-Off

Verified against [`temp_role_execution_plan.md`](temp_role_execution_plan.md) §4.3:

* [x] Every `Buyer(id)` issues at most `K = 2` `reserve` commands and sends **no** `pay` commands (`FR-6`, `FR-12`).
* [x] Every command sent on `mkt_req` (`reserve`, `cancel`, `confirm`, `withdraw`, `deliver`) immediately consumes its exact 1-to-1 reply on `buyer_ch[id]` or `seller_ch` (`FR-3`).
* [x] Both explicit `confirm(id, my_res)` and silent `confirm_timeout` paths are reachable in `DELIVERED` (`FR-11`).
* [x] Both `deliver` and non-delivery (`delivery_timeout`) paths are reachable in `PAID` (`FR-10`).
* [x] Zero busy-wait `do :: skip od` stuttering loops exist (consistent with M3's verification baseline in [`m3_ltl_and_counterexamples.md`](m3_ltl_and_counterexamples.md); ready for M4's final `run_checks.sh` gate).
