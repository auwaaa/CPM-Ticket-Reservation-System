# Role Execution & Recode Plan (v2 — Aligned with Revised Proposal)

> **Status:** `ACTIVE v2 — Updated for docs/revised_project_proposal.md`  
> **Course:** Verification of Concurrent Program Models · Winter Semester 2026 (VGU)  
> **Authoritative Specification:** [Revised Project Proposal](revised_project_proposal.md)  
> **Reference Documents:**  
> - [Team Plan](cpm_team_plan.md)  
> - [Repository Pipeline Architecture](repository_pipeline_architecture.md)  
> - [Shared PROMELA Definitions](../models/defs.pml)  
> - [SPIN Verification Script](../scripts/run_checks.sh)

---

## 0. Resolved Decisions & Recode Impact (`main` `f4ab8e3` $\rightarrow$ Revised Proposal v2)

### 0.1 Previously Open Decisions (Now Locked)
1. **Role Assignments (Confirmed):** **M1** = Khang (`10423055`), **M2** = Uy (`10423122`), **M3** = Nhân (`10423085`), **M4** = Kiệt (`10423067`).
2. **Authoritative Specification (Locked):** [`docs/revised_project_proposal.md`](revised_project_proposal.md) defines **FR-1–FR-12**, **Assumptions 1–7**, **7 Safety Properties (`S1`–`S7`)**, and **5 Liveness Properties (`L1`–`L5`)**.
3. **Canonical Channel & State Names (Locked):** `mkt_req`, `buyer_ch[N]`, `seller_ch`, `pay_req`, `pay_resp`, and `ticket_state`.
4. **Merge-Conflict Strategy (Locked):** **Option A** — single-file section markers (`/* === M1/M2/M3 SECTION START/END === */`) in `models/01_naive.pml` and `models/02_final.pml`.
5. **Windows 11 Toolchain:** `spin 6.5.1` + `gcc 15.1.0` (MSYS2/MinGW-w64) verified on Windows 11.

### 0.2 Recode Impact Matrix (Why Recoding Is Required)
M1 and M3 already merged a v1 baseline on `main` (`f4ab8e3`) *before* [`docs/revised_project_proposal.md`](revised_project_proposal.md) arrived. Four major specification changes require targeted recoding by **M1** and **M3** (while **M2** and **M4** have not pushed yet and can code straight to v2):

| Spec Change (Revised Proposal) | Previous v1 (`f4ab8e3`) | Required v2 Behavior | Who Recodes? |
| :--- | :--- | :--- | :--- |
| **FR-6 & FR-8(a): Auto-Charge on `reserve` + `charge_fail` Release** | Buyer sent separate `pay(b, r)` after `reserve_ok`; `charge_fail` kept state in `RESERVED`. | Drop `pay`/`pay_ok`/`pay_fail`. Accepting `reserve(b)` immediately dispatches `pay_req ! charge(b, r)`. `charge_fail(b, r)` matching active `(b, r)` releases `RESERVED -> AVAILABLE`. | **M1** (`defs.pml`, `Marketplace`), **M2** (`Buyer` codes directly to v2), **M3** (`01_naive.pml`) |
| **FR-11 & Assumption 6: `confirm_timeout` Replaces Old Assumption A9** | No confirmation timeout; Buyer was forced to always confirm after `DELIVERED`. | Add abstract `confirm_timeout` in `DELIVERED -> SETTLED` (triggers `payout`). Buyer may non-deterministically `confirm(b, r)` OR stay silent after `DELIVERED`. | **M1** (`Marketplace`), **M2** (`Buyer` codes directly to v2), **M3** (`01_naive.pml`) |
| **Assumption 7 & `S6`/`S7`: Integer Escrow Balances + Per-Charge Status** | Counter ledger (`charged_cnt`, `held_cnt`, `paidOut_cnt`, `refunded_cnt`). | Signed integer balances `short balance[N]` (init `INIT_BAL = K`), `short escrow = 0`, `short seller_bal = 0`, `B0 = N * INIT_BAL`, plus per-reservation `charge_status[r]` (`NONE/HELD/PAID_OUT/REFUNDED`) for `S6`. | **M1 & M3** (`defs.pml`), **M3** (`PaymentService`, `01_naive.pml`, `ltl`) |
| **Section 8: `S1`–`S7` & `L1`–`L5` (Replaces Old `S1`–`S9` & `L1`–`L3`)** | 9 safety + 3 liveness claims; `S8` forced `is_terminal -> held_cnt == 0`. | 7 safety (`S1`–`S7`) + 5 liveness (`L1`–`L5`). `S4` allows temporary stale funds in `escrow` until refunded (`L3`/`L4`), simplifying `Marketplace` terminal entry while requiring `end_mkt:` to keep draining `pay_resp`! | **M1** (`Marketplace` ghost updates + `end_mkt:` `pay_resp` drain), **M3** (`ltl` + `01_naive.pml`), **M4** (`run_checks.sh`) |

---

## 1. Global Orchestration — Ownership Boundaries & Sync Barriers

### 1.1 Ownership Matrix

| Slot | Assignee | Git Branch | Owned Files / Blocks (Write) | Read-Only Inputs | Primary Outputs |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **M1** | Nguyen Quoc Khang (`10423055`) | `feat/marketplace` | `models/defs.pml` (co-owner), `Marketplace()` & `init` in `models/02_final.pml`, Architecture & State Machine section in `docs/` | Revised Proposal FR-1–FR-11, M2/M3 contracts | Frozen `defs.pml` v2, hardened `Marketplace()` with auto-`charge`, `(current_buyer, current_res_id)` guards, `res/delivery/confirm` timeouts & stale-charge refund draining |
| **M2** | Pham Khac Uy (`10423122`) | `feat/participants` | `Seller()` and `Buyer(byte id)` in `models/02_final.pml` (and review of `01_naive.pml`), Processes & Assumptions section in `docs/` | Frozen `models/defs.pml` v2, FR-3/FR-4/FR-8/FR-10/FR-11/FR-12 | Bounded-attempt `Buyer(b)` ($K = 2$), non-deterministic `Seller()`, explicit-confirm vs. `confirm_timeout` coverage, spoofed/stale request path |
| **M3** | Truong Thien Nhan (`10423085`) | `feat/payment-ltl` | `models/defs.pml` (co-owner), `PaymentService()` in `01_naive.pml` & `02_final.pml`, all `ltl S1..S7` & `L1..L5` blocks, bug injection in `models/01_naive.pml`, LTL & Counterexamples section in `docs/` | Revised Proposal Section 7 & 8 (`S1`–`S7`, `L1`–`L5`) | Integer-escrow `PaymentService()`, per-charge `S6` guard, exact `S1`–`S7` & `L1`–`L5` specs, reproducible buggy `01_naive.pml` breaking `S1, S4, S5, S7` |
| **M4** | Vuong Gia Kiet (`10423067`) | `feat/verification` | `scripts/run_checks.sh`, `trails/*.trail`, `results/metrics.csv`, Verification/Scalability sections, final report & slides in `docs/` | `models/01_naive.pml`, `models/02_final.pml`, `models/defs.pml` | Automated safety/liveness runner (`S1`–`S7`, `L1`–`L5`), saved `.trail` artifacts, scalability CSV ($N, K, M$, compression/POR) & final report/slides |

### 1.2 Sync Barriers (Gates 0–5)

| Barrier | Timing | Owner(s) | Entry Criteria | Exit Gate (Pass Condition) | Unblocks |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **Barrier 0 (v2)** | Immediate Resync | **M1 & M3** (M2 & M4 review) | Revised proposal reviewed | `models/defs.pml` v2 frozen & merged to `main`; all 4 members approve | Parallel v2 recoding (`M1`, `M3`) and fresh coding (`M2`, `M4`) |
| **Barrier 1** | Section 1 Gate | **M1, M2, M3, M4** | Barrier 0 v2 passed | Happy-path simulation reaches `AVAILABLE -> RESERVED -> PAID -> DELIVERED -> SETTLED` with **0 deadlocks** and `S7` conserved | Section 2 failure modes & naive counterexamples |
| **Barrier 2** | Section 2 Gate | **M3 & M4** (M1 & M2 review) | Barrier 1 passed | `models/01_naive.pml` reproduces failures for **`S1`, `S4`, `S5`, `S7`** with saved `trails/01_naive_*.trail` | Section 3 hardening verification |
| **Barrier 3** | Section 3 Gate | **M1, M2, M3, M4** | Barrier 2 passed | `models/02_final.pml` passes deadlock-freedom, inline `assert`s, and **`S1`–`S7`** with **0 errors** via `run_checks.sh` | Section 4 liveness (`-a -f`) & scalability study |
| **Barrier 4** | Section 4 Gate | **M4** (All fix cycles) | Barrier 3 passed | `02_final.pml` passes **`L1`–`L5`** (`-a -f`) with **0 errors**; `results/metrics.csv` scalability matrix ($N=2,3,4$, $K$, 2 listings, compression/POR) complete | Section 5 final report, slides & clean submission run |
| **Barrier 5** | Section 5 Gate | **All Members** | Barrier 4 passed | Report, slides, `run_checks.sh`, `trails/`, and `.pml` bundle pass one clean end-to-end check on `main` | Final submission |

---

## 2. Barrier 0 (v2) Contract — Proposed Frozen `models/defs.pml` Interface

M1 and M3 must update [`models/defs.pml`](../models/defs.pml) to match the exact interface below (and get quick sign-off from M2 and M4):

### 2.1 Constants & Types
- **Parameters (overridable via `-DN=`, `-DK=` for M4 scalability):**
  - `#ifndef N` / `#define N 2` / `#endif`
  - `#ifndef K` / `#define K 2` / `#endif`
  - `#define INIT_BAL K` *(guarantees a buyer can fund up to `K` in-flight attempts without artificial deadlock)*
  - `#define B0 (N * INIT_BAL)`
  - `#define NO_BUYER 255`
  - `#define NO_RES 0`
  - `#define MAX_RES_ID ((N * K) + 2)` *(covers all unique reservation IDs `1..(N*K)` without wraparound)*
- **Per-charge status codes (for `S6`):**
  - `#define CHG_NONE     0`
  - `#define CHG_HELD     1`
  - `#define CHG_PAID_OUT 2`
  - `#define CHG_REFUNDED 3`
- **7 System States (`mtype:state`):** `AVAILABLE`, `RESERVED`, `PAID`, `DELIVERED`, `SETTLED`, `WITHDRAWN`, `REFUNDED`.
- **Protocol Messages (`mtype:msg`) — Note: `pay`/`pay_ok`/`pay_fail` removed per FR-6:**
  - Buyer $\leftrightarrow$ Marketplace: `reserve`, `reserve_ok`, `reserve_fail`, `cancel`, `cancel_ok`, `cancel_fail`, `confirm`, `confirm_ok`, `confirm_fail`.
  - Seller $\leftrightarrow$ Marketplace: `withdraw`, `withdraw_ok`, `withdraw_fail`, `deliver`, `deliver_ok`, `deliver_fail`.
  - Marketplace $\leftrightarrow$ PaymentService: `charge`, `charge_ok`, `charge_fail`, `payout`, `payout_ok`, `refund`, `refund_ok`.

### 2.2 Canonical Channel Signatures
| Channel | Direction | Signature | Payload Semantics |
| :--- | :--- | :--- | :--- |
| `mkt_req` | Buyers / Seller $\rightarrow$ Marketplace | `chan mkt_req = [4] of { mtype:msg, byte, byte };` | `{ msg_type, sender_id, res_id }` (`NO_RES` for `reserve`/`withdraw`/`deliver`) |
| `buyer_ch[N]` | Marketplace $\rightarrow$ `Buyer(id)` | `chan buyer_ch[N] = [2] of { mtype:msg, byte };` | `{ reply_msg, res_id }` — **1-to-1 replies to user commands (`reserve`, `cancel`, `confirm`) ONLY; never unsolicited payment updates** |
| `seller_ch` | Marketplace $\rightarrow$ Seller | `chan seller_ch = [2] of { mtype:msg };` | `{ reply_msg }` (`withdraw_ok/fail`, `deliver_ok/fail`) |
| `pay_req` | Marketplace $\rightarrow$ PaymentService | `chan pay_req = [2] of { mtype:msg, byte, byte };` | `{ cmd, buyer_id, res_id }` (`charge`, `payout`, `refund`) |
| `pay_resp` | PaymentService $\rightarrow$ Marketplace | `chan pay_resp = [2] of { mtype:msg, byte, byte };` | `{ reply_msg, buyer_id, res_id }` (`charge_ok`, `charge_fail`, `payout_ok`, `refund_ok`) |

### 2.3 Global State, Escrow Accounting & Ghost Variables
- **Core listing state (matching FR-1 / FR-4):**
  - `mtype:state ticket_state = AVAILABLE;`
  - `byte current_buyer  = NO_BUYER;` *(active reservation owner in `RESERVED`; locked sale winner in `PAID`/`DELIVERED`/`SETTLED`/`REFUNDED`)*
  - `byte current_res_id = NO_RES;`
  - `byte next_res_id    = 1;`
  - `bool deliveryConfirmed = false;` *(set `true` on explicit `confirm(b, r)` OR `confirm_timeout`)*
- **Signed integer escrow accounting (Assumption 7 & `S7`):**
  - `short balance[N] = INIT_BAL;` *(signed `short` so `S7` catches negative-balance bugs instead of silent `byte` wraparound; SPIN initializes all `N` elements to `INIT_BAL` at state 0)*
  - `short escrow     = 0;`
  - `short seller_bal = 0;`
  - `byte charge_status[MAX_RES_ID];` *(zero-initialized = `CHG_NONE`; tracks each reservation's single settlement for `S6`)*
- **Parametric `S7` helper macros (supports `-DN=2`, `-DN=3`, `-DN=4`):**
  ```promela
  #if N == 2
  #define SUM_BUYER_BAL  (balance[0] + balance[1])
  #define ALL_BAL_NONNEG (balance[0] >= 0 && balance[1] >= 0)
  #elif N == 3
  #define SUM_BUYER_BAL  (balance[0] + balance[1] + balance[2])
  #define ALL_BAL_NONNEG (balance[0] >= 0 && balance[1] >= 0 && balance[2] >= 0)
  #elif N == 4
  #define SUM_BUYER_BAL  (balance[0] + balance[1] + balance[2] + balance[3])
  #define ALL_BAL_NONNEG (balance[0] >= 0 && balance[1] >= 0 && balance[2] >= 0 && balance[3] >= 0)
  #endif
  ```
- **Auxiliary ghost variables (for `S1`–`S6`, `L1`–`L5`):**
  - `byte sale_count = 0;` *(incremented when entering `PAID`; `S1` requires `sale_count <= 1`)*
  - `byte sale_buyer = NO_BUYER;`, `byte sale_res_id = NO_RES;` *(latched on first entry to `PAID` so `S1` can assert `ever_paid -> (current_buyer == sale_buyer && current_res_id == sale_res_id)`)*
  - `bool ever_paid = false;`, `bool ever_delivered = false;`
  - `bool delivery_timed_out = false;` *(set `true` when `delivery_timeout` fires in `PAID`, supporting `L2`)*
  - `byte stale_refund_pending = 0;` *(incremented when stale `charge_ok(b, r)` arrives; decremented when its `refund_ok(b, r)` completes, supporting `L4`)*
  - `bool violation_mutex_reserve = false;` *(set `true` in naive model if a second buyer overwrites `RESERVED`; checked by `S2`)*
  - `bool violation_stale_accept = false;` *(set `true` if a mismatched `charge_ok` transitions to `PAID`; checked by `S4`)*
  - `bool violation_dup_settlement = false;` *(set `true` if `PaymentService` attempts duplicate `payout`/`refund` on the same `r`; checked by `S6`)*
  - `#define is_terminal (ticket_state == SETTLED || ticket_state == WITHDRAWN || ticket_state == REFUNDED)`

---

## 3. Subagent Brief — M1 (Marketplace & Core State Machine)

- **Role:** Marketplace & Core State Machine
- **Assignee:** Nguyen Quoc Khang (`10423055`)
- **Git Branch:** `feat/marketplace`
- **Owned Scope:** `models/defs.pml` (co-owner with M3), `proctype Marketplace()` and `init` in `models/02_final.pml`, System Architecture & State Machine section in `docs/`.

### 3.1 Required State-Transition Matrix (`Marketplace` in `02_final.pml`, per FR-1–FR-11)

| Current State | Event / Input | Guard Condition | Atomic State / Ghost Updates & Actions | Next State |
| :--- | :--- | :--- | :--- | :--- |
| `AVAILABLE` | `mkt_req ? reserve(b, _)` | `ticket_state == AVAILABLE && b < N` | `current_res_id = next_res_id; next_res_id++`; `current_buyer = b`; `ticket_state = RESERVED`; send `buyer_ch[b] ! reserve_ok(current_res_id)` AND immediately send `pay_req ! charge(b, current_res_id)` **(FR-4, FR-6)** | `RESERVED` |
| `AVAILABLE` | `mkt_req ? withdraw(_, _)` | `ticket_state == AVAILABLE` | `ticket_state = WITHDRAWN`; send `seller_ch ! withdraw_ok` **(FR-5)** | `WITHDRAWN` |
| `RESERVED` | `pay_resp ? charge_ok(b, r)` | `ticket_state == RESERVED && b == current_buyer && r == current_res_id && r != NO_RES` | `ever_paid = true`; `sale_count++`; `sale_buyer = b`; `sale_res_id = r`; `ticket_state = PAID` **(FR-7)** *(no unsolicited `buyer_ch[b]` send)* | `PAID` |
| `RESERVED` | `pay_resp ? charge_fail(b, r)` | `ticket_state == RESERVED && b == current_buyer && r == current_res_id` | Release reservation: `current_buyer = NO_BUYER`; `current_res_id = NO_RES`; `ticket_state = AVAILABLE` **(FR-8a)** | `AVAILABLE` |
| `RESERVED` | `mkt_req ? cancel(b, r)` | `ticket_state == RESERVED && b == current_buyer && r == current_res_id && r != NO_RES && b < N` | Release reservation: `current_buyer = NO_BUYER`; `current_res_id = NO_RES`; `ticket_state = AVAILABLE`; send `buyer_ch[b] ! cancel_ok(r)` **(FR-8b)** | `AVAILABLE` |
| `RESERVED` | Abstract `res_timeout` | `ticket_state == RESERVED` | Release reservation: `current_buyer = NO_BUYER`; `current_res_id = NO_RES`; `ticket_state = AVAILABLE` **(FR-8c)** | `AVAILABLE` |
| *Any (incl. terminal `end_mkt:`)* | `pay_resp ? charge_ok(b, r)` *(stale)* | `ticket_state != RESERVED \|\| b != current_buyer \|\| r != current_res_id` | **Do NOT mutate listing state or `(current_buyer, current_res_id)`.** `stale_refund_pending++`; immediately send `pay_req ! refund(b, r)` **(FR-9, S4, L3, L4)** | *(unchanged)* |
| *Any (incl. terminal `end_mkt:`)* | `pay_resp ? charge_fail(b, r)` *(stale)* | `ticket_state != RESERVED \|\| b != current_buyer \|\| r != current_res_id` | Ignore (no state change, no refund needed) | *(unchanged)* |
| *Any (incl. terminal `end_mkt:`)* | `pay_resp ? refund_ok(b, r)` | *(stale or active refund ack)* | If `r != sale_res_id \|\| ticket_state != REFUNDED`: decrement `stale_refund_pending--` (if `> 0`) **(L4)** | *(unchanged)* |
| *Any (incl. terminal `end_mkt:`)* | `pay_resp ? payout_ok(b, r)` | *(payout ack)* | Consume cleanly | *(unchanged)* |
| `PAID` | `mkt_req ? deliver(_, _)` | `ticket_state == PAID` | `ever_delivered = true`; `ticket_state = DELIVERED`; send `seller_ch ! deliver_ok` **(FR-10a)** | `DELIVERED` |
| `PAID` | Abstract `delivery_timeout` | `ticket_state == PAID` | `delivery_timed_out = true`; `ticket_state = REFUNDED`; send `pay_req ! refund(current_buyer, current_res_id)` **(FR-10b)** | `REFUNDED` |
| `DELIVERED` | `mkt_req ? confirm(b, r)` | `ticket_state == DELIVERED && b == current_buyer && r == current_res_id && r != NO_RES && b < N` | `deliveryConfirmed = true`; `ticket_state = SETTLED`; send `pay_req ! payout(b, r)` AND `buyer_ch[b] ! confirm_ok(r)` **(FR-11a)** | `SETTLED` |
| `DELIVERED` | Abstract `confirm_timeout` | `ticket_state == DELIVERED` | `deliveryConfirmed = true`; `ticket_state = SETTLED`; send `pay_req ! payout(current_buyer, current_res_id)` **(FR-11b, Assumption 6)** | `SETTLED` |
| *Any (incl. terminal `end_mkt:`)* | Wrong-state or unauthorized command | Guard fails | Reject without mutating state: reply `reserve_fail`/`cancel_fail`/`confirm_fail`/`withdraw_fail`/`deliver_fail` **(FR-3)** | *(unchanged)* |

### 3.2 Exact M1 Recode Tasks (From Current `main` `f4ab8e3`)
1. **Barrier 0 v2 (`models/defs.pml`):** Sync with M3 to adopt the Section 2 contract (`current_buyer`, remove `pay*`, signed `short balance[N]`/`escrow`/`seller_bal`, `charge_status[]`, `SUM_BUYER_BAL`/`ALL_BAL_NONNEG`, and `S1`–`S7`/`L1`–`L5` ghost vars).
2. **Recode `Marketplace()` in `models/02_final.pml`:**
   - Remove the `msg == pay` handler; dispatch `pay_req ! charge(b, current_res_id)` directly inside `msg == reserve` right after `reserve_ok` (FR-6).
   - Update `charge_fail` to release `RESERVED -> AVAILABLE` when matching active `(b, r)` (FR-8a), and remove all `buyer_ch[b] ! pay_ok/pay_fail` sends.
   - Replace `reserved_by`/`buyer_of_sale` with unified `current_buyer` (plus `sale_buyer`/`sale_res_id` latch on `PAID` for `S1`).
   - Add the 3rd abstract timeout: `confirm_timeout` in `DELIVERED -> SETTLED` triggering `pay_req ! payout(current_buyer, current_res_id)` (FR-11b).
   - Remove the old `withdraw_pending`/`payout_done`/`refund_done` holding logic (no longer needed under `S4` + `L3`/`L4`), and instead make **`end_mkt:` handle BOTH `mkt_req ? msg, b, r` (rejecting late user commands) AND `pay_resp ? msg, b, r` (refunding any late `charge_ok(b, r)` and decrementing `stale_refund_pending` on stale `refund_ok`)**!
3. **Section 3–4 (Integration & Liveness Fixes):** Collaborate with M2, M3, and M4 to fix any deadlock, safety (`S1`–`S7`), or weak-fairness liveness (`L1`–`L5`) issues.
4. **Section 5 (Final Report):** Write the **System Architecture & Marketplace State Machine** section (transition table, FR-1–FR-11 mapping, and how `(b, r)` + `d_step` + `end_mkt:` draining eliminate ABA stale-charge races and delivery/confirmation races).

### 3.3 Acceptance Criteria (Definition of Done)
- [ ] `models/defs.pml` v2 frozen and approved by all 4 members.
- [ ] `Marketplace()` never sends unsolicited messages on `buyer_ch[b]` (strict 1-to-1 replies per FR-3).
- [ ] `charge_fail(b, r)` releases `RESERVED -> AVAILABLE`; stale `charge_ok(b, r)` triggers `pay_req ! refund(b, r)` in *every* state (including `end_mkt:`) without mutating `ticket_state`.
- [ ] `DELIVERED` resolves via both explicit `confirm(b, r)` and `confirm_timeout`.
- [ ] `02_final.pml` compiles cleanly (`spin -a` + `gcc`) and passes deadlock-freedom + `S1`–`S7` + `L1`–`L5`.

### 3.4 Pitfalls & Constraints
- **Never put blocking channel sends/receives inside `d_step`:** Use `d_step` strictly for deterministic variable/ghost updates, and place channel sends immediately after `d_step`.
- **Keep `end_mkt:` draining `pay_resp`:** If `end_mkt:` only drained `mkt_req`, a late `charge_ok` arriving after `WITHDRAWN`/`REFUNDED`/`SETTLED` would stay in `escrow` forever and fail `L3` and `L4`!
- **Watch `pay_req` / `pay_resp` capacity when scaling `N = 4`:** With auto-charge on `reserve`, at most `N * K` charges can occur over the whole run; if `N = 4` ever fills `pay_req [2]` + `pay_resp [2]` simultaneously, coordinate with M3/M4 to size `pay_req`/`pay_resp` cleanly (e.g., `[4]` or keep `[2]` if verified deadlock-free at `N = 4`).

---

## 4. Subagent Brief — M2 (Participants: Seller & Buyer Processes)

- **Role:** Participants (`Seller` and `Buyer(byte id)`)
- **Assignee:** Pham Khac Uy (`10423122`)
- **Git Branch:** `feat/participants`
- **Owned Scope:** `proctype Seller()` and `proctype Buyer(byte id)` in `models/02_final.pml` (and review of `01_naive.pml`), Processes & Assumptions section of the final report.

### 4.1 Behavioral Contracts (Aligned with Revised Proposal FR-3, FR-4, FR-6, FR-8, FR-10, FR-11, FR-12)
1. **`Buyer(byte id)` (`id` in `0..N-1`):**
   - **Bounded Attempts (`K = 2`, FR-12):** Loop at most `K` reservation attempts (`byte attempts = 0;`). Send `mkt_req ! reserve(id, NO_RES)` and read reply `buyer_ch[id] ? reply, my_res`. *(Do NOT send a `pay` command — Marketplace auto-charges on `reserve_ok` per FR-6!)*
   - **After `reserve_ok(my_res)`:** Non-deterministically choose one of:
     1. **Cancel (racing with in-flight `charge`):** Send `mkt_req ! cancel(id, my_res)` and read `buyer_ch[id] ? reply, tmp_r`.
     2. **Wait / Abandon:** Do not send `cancel` (allows `charge_ok`, `charge_fail`, or `res_timeout` to resolve `RESERVED`).
   - **In `DELIVERED` when `current_buyer == id` (FR-11 & Assumption 6):** Non-deterministically choose one of:
     1. **Explicit confirmation:** Send `mkt_req ! confirm(id, my_res)` and read `buyer_ch[id] ? reply, tmp_r`.
     2. **Silence / non-confirmation:** Do not send `confirm` (allows `Marketplace`'s `confirm_timeout` to auto-confirm and move `DELIVERED -> SETTLED`).
   - **Spoofed / Stale Request Path (bounded once per buyer):** Non-deterministically allow a non-owning buyer (`current_buyer != id`) to send a spoofed/stale `cancel(id, 1)` or `confirm(id, 1)` and read its reply from `buyer_ch[id]` — proving `02_final.pml` rejects unauthorized requests without mutating state (and helping expose `S5` defects in `01_naive.pml`).
   - **Clean Termination:** Exit cleanly once `is_terminal` holds (or once `attempts >= K` and `current_buyer != id` and spoof branch finished/skipped).
2. **`Seller()`:**
   - While `ticket_state == AVAILABLE`, non-deterministically choose to **withdraw** (`mkt_req ! withdraw(0, NO_RES); seller_ch ? _`) or wait for a sale.
   - While `ticket_state == PAID`, non-deterministically choose between:
     1. **Deliver:** `mkt_req ! deliver(0, NO_RES); seller_ch ? _` (racing with `delivery_timeout` per FR-10).
     2. **Non-delivery failure:** Do not send `deliver` (allowing `delivery_timeout` to trigger `REFUNDED` and verify `L2`).
   - Exit cleanly on `is_terminal`.

### 4.2 Step-by-Step Tasks
1. **Barrier 0 v2:** Review and sign off on `models/defs.pml` v2 (especially `K = 2`, removal of `pay`, and 1-to-1 `buyer_ch[N]` replies).
2. **Section 1–3 (`models/02_final.pml`):** Implement `Seller()` and `Buyer(byte id)` inside the `/* === M2 SECTION START/END === */` block of `02_final.pml` directly to the v2 contract above. Review M3's temporary `Seller`/`Buyer` in `01_naive.pml` for consistency.
3. **Section 4:** Collaborate with M1 and M4 to eliminate any liveness acceptance cycles (`L1`–`L5`) or deadlocks.
4. **Section 5:** Write the **Participants (`Seller` & `Buyer`) & Modeling Assumptions (Assumptions 1–7)** section of the final report, explicitly explaining FR-12 (`K = 2`) and FR-11 (`confirm` vs. `confirm_timeout`).

### 4.3 Acceptance Criteria (Definition of Done)
- [ ] Every `Buyer(id)` issues at most `K` `reserve` commands and sends NO `pay` commands.
- [ ] Every command sent to `mkt_req` (`reserve`, `cancel`, `confirm`, `withdraw`, `deliver`) immediately reads its exact 1-to-1 reply from `buyer_ch[id]` or `seller_ch`.
- [ ] Both explicit `confirm(id, my_res)` and silent `confirm_timeout` paths are reachable in `DELIVERED`.
- [ ] Both `deliver` and non-delivery (`delivery_timeout`) paths are reachable in `PAID`.
- [ ] No busy-wait `do :: skip od` stuttering loops that break `L1`–`L5`.

---

## 5. Subagent Brief — M3 (Payment Service, LTL Specification & Naive Buggy Model)

- **Role:** Payment Service, LTL Properties (`S1`–`S7`, `L1`–`L5`) & Buggy Baseline Model
- **Assignee:** Truong Thien Nhan (`10423085`)
- **Git Branch:** `feat/payment-ltl`
- **Owned Scope:** `models/defs.pml` (co-owner with M1), `proctype PaymentService()` in `01_naive.pml` & `02_final.pml`, all inline `assert(...)` and `ltl S1..S7` / `L1..L5` blocks, bug injection in `models/01_naive.pml`, LTL & Counterexamples section of the final report.

### 5.1 `PaymentService` Contract (Assumption 7, `S6`, `S7`)
Loop at `end_payment:` reading `pay_req ? cmd, b, r`:
- **`charge(b, r)`:**
  - Non-deterministically choose:
    - **Success (requires `b < N && balance[b] >= 1 && r > NO_RES && r < MAX_RES_ID && charge_status[r] == CHG_NONE`):**
      ```promela
      d_step {
          balance[b]--;
          escrow++;
          charge_status[r] = CHG_HELD;
          assert(SUM_BUYER_BAL + escrow + seller_bal == B0);
          assert(ALL_BAL_NONNEG && escrow >= 0 && seller_bal >= 0)
      };
      pay_resp ! charge_ok(b, r)
      ```
    - **Failure:** `pay_resp ! charge_fail(b, r)`
- **`payout(b, r)`:**
  - Enforce single settlement (`S6`): assert `r > NO_RES && r < MAX_RES_ID && charge_status[r] == CHG_HELD && escrow >= 1`.
  - Atomically (`d_step`): `escrow--; seller_bal++; charge_status[r] = CHG_PAID_OUT;` + assert `S7` conservation.
  - Send `pay_resp ! payout_ok(b, r)`.
- **`refund(b, r)`:**
  - Enforce single settlement (`S6`): assert `b < N && r > NO_RES && r < MAX_RES_ID && charge_status[r] == CHG_HELD && escrow >= 1`.
  - Atomically (`d_step`): `escrow--; balance[b]++; charge_status[r] = CHG_REFUNDED;` + assert `S7` conservation.
  - Send `pay_resp ! refund_ok(b, r)`.

### 5.2 Authoritative `S1`–`S7` & `L1`–`L5` LTL Specification Table (From Revised Proposal Section 8)

| ID | Type | Property Name | PROMELA `ltl` Structure (No `X` operator — preserves POR) |
| :--- | :---: | :--- | :--- |
| **S1** | Safety | At-Most-Once Sale | `[] ((sale_count <= 1) && (ever_paid -> (current_buyer == sale_buyer && current_res_id == sale_res_id && current_buyer != NO_BUYER)))` |
| **S2** | Safety | Mutual Exclusion of Reservations | `[] (!violation_mutex_reserve && (ticket_state == RESERVED -> (current_buyer != NO_BUYER && current_res_id != NO_RES)))` |
| **S3** | Safety | Withdrawal Integrity | `[] (ticket_state == WITHDRAWN -> (!ever_paid && !ever_delivered && current_buyer == NO_BUYER && [] (ticket_state == WITHDRAWN)))` |
| **S4** | Safety | No Stale Charge Acceptance | `[] (!violation_stale_accept)` *(+ inline guard checking that any `charge_ok(b, r)` accepted into `PAID` matched active `(current_buyer, current_res_id)` in `RESERVED`, and `payout` only pays `sale_res_id`)* |
| **S5** | Safety | Confirmed Delivery Before Payout | `[] (seller_bal > 0 -> (ever_delivered && deliveryConfirmed && ticket_state == SETTLED))` *(ensure `ticket_state = SETTLED` & `deliveryConfirmed = true` are set before `pay_req ! payout`)* |
| **S6** | Safety | Single Settlement per Charge | `[] (!violation_dup_settlement && seller_bal <= 1)` *(+ `PaymentService` asserts `charge_status[r] == CHG_HELD` before `payout`/`refund` and transitions to `CHG_PAID_OUT`/`CHG_REFUNDED` once)* |
| **S7** | Safety | Strict Money Conservation | `[] ((SUM_BUYER_BAL + escrow + seller_bal == B0) && ALL_BAL_NONNEG && escrow >= 0 && seller_bal >= 0)` |
| **L1** | Liveness | Reservation Termination | `[] (ticket_state == RESERVED -> <> (ticket_state == AVAILABLE \|\| ticket_state == PAID))` |
| **L2** | Liveness | Non-Delivery Refund | `[] ((ticket_state == PAID && delivery_timed_out) -> <> (ticket_state == REFUNDED && charge_status[sale_res_id] == CHG_REFUNDED))` *(or `[] (ticket_state == PAID -> <> (ever_delivered \|\| (ticket_state == REFUNDED && escrow == 0)))`)* |
| **L3** | Liveness | Escrow Resolution | `[] (escrow > 0 -> <> (escrow == 0))` |
| **L4** | Liveness | Late-Payment Refund | `[] (stale_refund_pending > 0 -> <> (stale_refund_pending == 0))` |
| **L5** | Liveness | Post-Sale Termination | `[] (ticket_state == PAID -> <> (ticket_state == SETTLED \|\| ticket_state == REFUNDED))` |

*(Note on `S3` in `-DSAFETY` mode: SPIN's `-DSAFETY` supports safety LTL with nested `[]`, or simplify `S3` to `!violation_bad_withdraw && (ticket_state == WITHDRAWN -> (!ever_paid && !ever_delivered && current_buyer == NO_BUYER))` if `-DSAFETY` flags nested temporal operators — verify with `spin -a` + `gcc -DSAFETY`!)*

### 5.3 Intentional Bug Injection Spec for `models/01_naive.pml` (Revised Targets: `S1`, `S4`, `S5`, `S7`)
Update [`models/01_naive.pml`](../models/01_naive.pml) to the v2 auto-charge protocol and inject 4 clean concurrency defects matching the revised proposal:
1. **Break `S1` (Double-sale / race):** Omit `ticket_state == RESERVED` / `res_id` guards on `charge_ok` (allowing a second/stale `charge_ok` to overwrite `current_buyer`, `current_res_id`, and increment `sale_count > 1`).
2. **Break `S4` (ABA Stale-charge acceptance):** Drop `r == current_res_id` check on `charge_ok(b, r)` (checking only `b == current_buyer`!) so a delayed `charge_ok(b, r1)` from buyer `b`'s expired attempt 1 is misapplied to attempt 2 (`r2`), setting `violation_stale_accept = true`!
3. **Break `S5` (Payout without confirmed delivery):** Allow `confirm` / `payout` while in `PAID` (before `DELIVERED`) or without `deliveryConfirmed`, so `seller_bal > 0` occurs before confirmed delivery.
4. **Break `S7` (Money conservation / escrow bug):** Omit `escrow--` or allow stale `charge_ok` / unguarded `refund` to lose or double-credit funds in naive `PaymentService`, breaking `SUM_BUYER_BAL + escrow + seller_bal == B0` (and also breaking `L3`/`L4` by dropping stale `charge_ok` without refund).

### 5.4 Exact M3 Recode Tasks (From Current `main` `f4ab8e3`)
1. **Barrier 0 v2:** Co-author `models/defs.pml` v2 with M1 (signed `short` balances, `charge_status[]`, `SUM_BUYER_BAL`/`ALL_BAL_NONNEG`, v2 ghost vars).
2. **Recode `PaymentService()` & `ltl S1..S7 / L1..L5` in `models/02_final.pml`:** Switch from `charged_cnt`/`held_cnt` counters to Assumption 7 integer balances (`balance[N]`, `escrow`, `seller_bal`) + `charge_status[r]` (`S6`), and replace `S1`–`S9`/`L1`–`L3` with exact **`S1`–`S7` & `L1`–`L5`**.
3. **Update `models/01_naive.pml`:** Align to v2 protocol (auto-`charge` on `reserve`, no `pay`, integer balances) and confirm reproducible counterexamples for **`S1`, `S4`, `S5`, `S7`**.
4. **Section 4–5:** Refine any liveness predicates if `-a -f` surfaces edge cases, and write the **LTL Specification (`S1`–`S7`, `L1`–`L5`) & Counterexample Analysis** section of the report.

### 5.5 Acceptance Criteria (Definition of Done)
- [ ] `PaymentService()` preserves `SUM_BUYER_BAL + escrow + seller_bal == B0` and non-negative balances on every reachable state in `02_final.pml`.
- [ ] All 12 claims (`ltl S1`..`ltl S7` and `ltl L1`..`ltl L5`) match the revised proposal Section 8 and use no `X` operator.
- [ ] `01_naive.pml` reliably fails on **`S1`, `S4`, `S5`, `S7`** for M4 trail capture.

---

## 6. Subagent Brief — M4 (SPIN Verification, Automation, Scalability & Report Lead)

- **Role:** SPIN Verification, Automation, Scalability & Report Lead
- **Assignee:** Vuong Gia Kiet (`10423067`)
- **Git Branch:** `feat/verification`
- **Owned Scope:** [`scripts/run_checks.sh`](../scripts/run_checks.sh), `trails/*.trail`, [`results/`](../results/) (`metrics.csv`), final report compilation & presentation slides.

### 6.1 Required Fixes & Upgrades to `scripts/run_checks.sh`
1. **Critical Bug — Remove `-E` from primary safety/deadlock run (Line 58):** `./pan -E` suppresses deadlock detection. Run `./pan` without `-E` for deadlock-freedom.
2. **Automate All 12 Revised Named LTL Properties (`S1`–`S7` and `L1`–`L5`):**
   - Safety pass (`gcc -O2 -DSAFETY -o pan pan.c`): run `./pan` (deadlocks + assertions) and `./pan -N S1` through `./pan -N S7`.
   - Liveness pass (`gcc -O2 -o pan pan.c`, **NO `-DSAFETY`**): run `./pan -a -f -N L1` through `./pan -a -f -N L5`.
3. **Implement `capture_trail()`:** On any `errors: >0` for `<prop>` on `<model>`, copy/move `*.trail` to `trails/${MODEL_BASE}_${prop}.trail` (tracked by `!trails/*.trail`).
4. **Align `results/metrics.csv` Header:**
   `timestamp,model,property,N_buyers,K_retries,M_listings,flags,errors,states,transitions,memory_MB,runtime_s,result`
5. **Add Scalability Benchmark Matrix (per Revised Proposal Section 3):**
   - Vary `N = 2, 3, 4` (`-DN=2`, `-DN=3`, `-DN=4`) and `K` (`-DK=1`, `-DK=2`, `-DK=3`).
   - Add 2-listing study (`M = 1, 2`) if implemented in Section 4.
   - Compare flags: baseline (`-O2`), `-DCOLLAPSE`, `-DBITSTATE`, and `-DNOREDUCE` (POR savings).
6. **Windows 11 Git Bash Compatibility:** Handle `pan.exe` cleanly and clean up `pan*` and `_spin_nvr.tmp` on exit without touching `trails/*.trail`.

### 6.2 Step-by-Step Tasks
1. **Barrier 0 v2:** Review `models/defs.pml` v2 (`-DN=`, `-DK=`, `SUM_BUYER_BAL` macro for `N=2,3,4`).
2. **Section 1:** Fix `-E`, add `S1`–`S7` / `L1`–`L5` loops, `capture_trail()`, and CSV schema in `scripts/run_checks.sh`.
3. **Section 2 (Barrier 2):** Run `run_checks.sh` on `models/01_naive.pml`; commit `trails/01_naive_S1.trail`, `01_naive_S4.trail`, `01_naive_S5.trail`, `01_naive_S7.trail`; export readable `spin -t -p -g -l` logs for M3.
4. **Section 3 (Barrier 3):** Run deadlock + assertion + `S1`–`S7` suite on `models/02_final.pml`; log metrics to `results/metrics.csv`.
5. **Section 4 (Barrier 4):** Run `L1`–`L5` under weak fairness (`-a -f`), then run the full scalability study (`N = 2, 3, 4`; varying `K`; 2-listing study; `-DCOLLAPSE`, `-DBITSTATE`, `-DNOREDUCE`) and populate `results/metrics.csv`.
6. **Section 5 (Barrier 5):** Compile all sections into the final report and presentation slides; run one final clean pass of `./scripts/run_checks.sh models/02_final.pml` on `main`.

### 6.3 Acceptance Criteria (Definition of Done)
- [ ] `scripts/run_checks.sh` enforces deadlock freedom (no `-E`), checks `S1`–`S7` and `L1`–`L5`, captures trails to `trails/`, and logs rows to `results/metrics.csv`.
- [ ] All 4 naive counterexample trails (`S1`, `S4`, `S5`, `S7`) are saved in `trails/` and replay cleanly via `spin -t -k trails/01_naive_<prop>.trail -p -g -l models/01_naive.pml`.
- [ ] `02_final.pml` passes `S1`–`S7` and `L1`–`L5` (`-a -f`) with `errors: 0`.
- [ ] `results/metrics.csv` contains complete baseline and scalability metrics (`N=2,3,4`, `K`, 2 listings, `-DCOLLAPSE`, `-DBITSTATE`, POR comparison).

---

## 7. Daily Integration, Git & Review Protocol (All Members)

1. **Branching & PRs:** Develop strictly on `feat/marketplace`, `feat/participants`, `feat/payment-ltl`, and `feat/verification`. Open PRs into `main`; never force-push `main`.
2. **Main Branch Gate:** Before merging any PR to `main` (starting at Barrier 1), run `./scripts/run_checks.sh` on the target model and verify no temporary `pan*` or `_spin_nvr.tmp` artifacts are staged.
3. **Nightly Sync:** Review the active Barrier in Section 1.2 together, confirm green gate output, and paste generated traces/tables directly into the report draft.
4. **Single Source of Truth:** All functional requirements, assumptions, and verification properties follow [`docs/revised_project_proposal.md`](revised_project_proposal.md).
