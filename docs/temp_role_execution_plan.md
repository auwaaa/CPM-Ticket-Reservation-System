# Temporary Role Execution Plan (Subagent-Style Task Briefs)

> **Status:** `DRAFT / TEMPORARY — For Group 2 Review & Editing before Sprint Execution`  
> **Course:** Verification of Concurrent Program Models · Winter Semester 2026 (VGU)  
> **Reference Documents:**  
> - [Team Plan](cpm_team_plan.md)  
> - [Repository Pipeline Architecture](repository_pipeline_architecture.md)  
> - [Repository README](../README.md)  
> - [Shared PROMELA Definitions](../models/defs.pml)  
> - [SPIN Verification Script](../scripts/run_checks.sh)

---

## 0. Open Decisions to Confirm During Team Review

Resolve and lock these 5 items before starting Day 1 implementation:

1. **Role Assignments (Confirmed):**
   - **M1** = Nguyen Quoc Khang (`10423055`)
   - **M2** = Pham Khac Uy (`10423122`)
   - **M3** = Truong Thien Nhan (`10423085`)
   - **M4** = Vuong Gia Kiet (`10423067`)
2. **Authoritative Definitions for `S1`–`S9`, `L1`–`L3`, and Assumptions `A1`–`A9`:**
   - The repository currently references `S1`, `S5`, `S8`, `S9`, `L1`–`L3`, `A1`, `A6`, and `A9`, but the full numbered proposal specification is not yet committed in `docs/`.
   - **Action needed:** Paste or commit the authoritative numbered list of `S1`–`S9`, `L1`–`L3`, and `A1`–`A9` into `docs/` so **M3** can lock exact property names, predicates, and semantics without guesswork.
3. **`models/defs.pml` Interface Discrepancies:**
   Current [`models/defs.pml`](../models/defs.pml) diverges from [`docs/repository_pipeline_architecture.md`](repository_pipeline_architecture.md) and [`docs/cpm_team_plan.md`](cpm_team_plan.md) in four ways that must be reconciled in Hour 1–2:
   - **Naming mismatches:** `defs.pml` uses `mkt_req`, `pay_req`, `pay_resp`, and `ticket_state`, whereas the architecture doc references `to_mkt`, `to_pay`, `from_pay`, and `state`. Pick one canonical set and update docs/models consistently.
   - **Missing `res_id` field in channels:** `mkt_req` (`{ mtype:msg, byte }`), `buyer_ch[N]` (`{ mtype:msg }`), `pay_req` (`{ mtype:msg, byte }`), and `pay_resp` (`{ mtype:msg, byte }`) currently lack a reservation ID field. Channels must carry `res_id` to support `pay(b, r)`, `cancel(b, r)`, `confirm(b, r)`, `reserve_ok(r)`, and stale-charge detection (`charge(b, r)` / `charge_ok(b, r)` / `refund(b, r)`).
   - **Missing constants and state/ghost variables:** `defs.pml` does not yet define `K` (`2`), `NO_RES` (`0`), `current_res_id`, `next_res_id`, or `deliveryConfirmed`.
   - **Money ledger booleans vs. counters:** `defs.pml` currently declares `bool charged`, `held`, `paidOut`, `refunded`. **Warning:** If a stale charge is refunded (`refunded = true`) AND a subsequent valid reservation settles (`paidOut = true`), single booleans will have both `refunded == true` and `paidOut == true`, breaking naive conservation assertions unless integer counters (`charged_cnt`, `held_cnt`, `paidOut_cnt`, `refunded_cnt`) or explicit per-sale/stale-refund ghost variables are used.
4. **Merge-Conflict Prevention in `01_naive.pml` and `02_final.pml`:**
   - Choose one workflow before coding:
     - **Option A (Single-file section markers):** Keep only `models/01_naive.pml` and `models/02_final.pml` with strict non-overlapping `/* === M1 / M2 / M3 SECTION === */` blocks and coordinated PR merge order.
     - **Option B (`#include` component files):** Split process implementations into component `.pml` files (`marketplace.pml`, `participants.pml`, `payment.pml`, `ltl_specs.pml`) included by `01_naive.pml` and `02_final.pml` for zero-conflict parallel editing. *(Note: update `.gitignore` / `cpm_team_plan.md` if choosing Option B.)*
5. **Windows 11 Toolchain Readiness:**
   - Confirm all 4 members have `spin.exe`, `gcc.exe` (MSYS2/MinGW-w64), and Git Bash installed, on `PATH`, and verified by running `spin -V` and `gcc --version`.

---

## 1. Global Orchestration — Ownership Boundaries & Sync Barriers

### 1.1 Ownership Matrix

| Slot | Assignee | Git Branch | Owned Files / Blocks (Write) | Read-Only Inputs | Primary Outputs |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **M1** | Nguyen Quoc Khang (`10423055`) | `feat/marketplace` | `models/defs.pml` (co-owner), `Marketplace()` in `models/02_final.pml` (and base `Marketplace()` for happy path), `init` coordination, Architecture section in `docs/` | Proposal state machine, M2/M3 channel contracts | Frozen `defs.pml`, hardened `Marketplace()` with serialisation, guards, timeouts & stale-charge refunds |
| **M2** | Pham Khac Uy (`10423122`) | `feat/participants` | `Seller()` and `Buyer(byte id)` in `models/01_naive.pml` & `models/02_final.pml`, Processes & Assumptions section in `docs/` | Frozen `models/defs.pml`, Assumption A9 & retry bound `K = 2` | Bounded-retry `Buyer(b)`, non-deterministic `Seller()`, A9-compliant post-delivery confirmation |
| **M3** | Truong Thien Nhan (`10423085`) | `feat/payment-ltl` | `models/defs.pml` (co-owner), `PaymentService()` in `01_naive.pml` & `02_final.pml`, all `ltl` blocks & `assert(...)`, bug injection in `models/01_naive.pml`, LTL & Counterexamples section in `docs/` | Proposal `S1`–`S9` & `L1`–`L3`, M1/M2 happy-path processes | `PaymentService()` ledger, `S1`–`S9` & `L1`–`L3` specs, reproducible buggy `01_naive.pml` |
| **M4** | Vuong Gia Kiet (`10423067`) | `feat/verification` | `scripts/run_checks.sh`, `trails/*.trail`, `results/metrics.csv`, Verification/Scalability sections, final report & slides in `docs/` | `models/01_naive.pml`, `models/02_final.pml`, `models/defs.pml` | Automated safety/liveness runner, saved `.trail` artifacts, scalability CSV & compiled report/slides |

### 1.2 Sync Barriers (Gates 0–5)

| Barrier | Timing | Owner(s) | Entry Criteria | Exit Gate (Pass Condition) | Unblocks |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **Barrier 0** | Day 1, Hours 1–2 | **M1 & M3** (M2 & M4 review) | Open Decisions #2–#4 resolved | `models/defs.pml` frozen & merged to `main`; all 4 members approve | Parallel process coding (`M1`, `M2`, `M3`) and runner updates (`M4`) |
| **Barrier 1** | End of Day 1 | **M1, M2, M3, M4** | Barrier 0 passed | Happy-path simulation reaches `AVAILABLE -> RESERVED -> PAID -> DELIVERED -> SETTLED` with **0 deadlocks** | Day 2 failure-mode & naive bug injection |
| **Barrier 2** | End of Day 2 | **M3 & M4** (M1 & M2 supply failure modes) | Barrier 1 passed | `models/01_naive.pml` reproduces failures for `S1`, `S5`, `S8`, `S9` with saved `trails/01_naive_*.trail` | Day 3 hardening in `02_final.pml` |
| **Barrier 3** | End of Day 3 | **M1, M3, M4** (M2 confirms A9) | Barrier 2 passed | `models/02_final.pml` passes deadlock, assertions, and `S1`–`S9` with **0 errors** via `run_checks.sh` | Day 4 liveness (`-a -f`) & scalability study |
| **Barrier 4** | End of Day 4 | **M4** (All fix cycles) | Barrier 3 passed | `02_final.pml` passes `L1`–`L3` (`-a -f`, A6/A9) with **0 errors**; `results/metrics.csv` scalability matrix complete | Day 5 final report, slides & clean submission run |
| **Barrier 5** | End of Day 5 | **All Members** | Barrier 4 passed | Report, slides, `run_checks.sh`, `trails/`, and `.pml` bundle pass one clean end-to-end check on `main` | Final submission |

---

## 2. Barrier 0 Contract — Proposed Frozen `models/defs.pml` Interface

M1 and M3 must finalize [`models/defs.pml`](../models/defs.pml) in Hours 1–2 of Day 1 using the canonical interface below (or an explicitly agreed variant approved by M2 and M4):

### 2.1 Constants & Types
- **Parameters:** `#define N 2` (guarded by `#ifndef N` so M4 can override with `-DN=3`, `-DN=4`), `#define K 2` (bounded buyer retry limit), `#define NO_BUYER 255`, `#define NO_RES 0`.
- **7 System States (`mtype:state`):** `AVAILABLE`, `RESERVED`, `PAID`, `DELIVERED`, `SETTLED`, `WITHDRAWN`, `REFUNDED`.
- **Protocol Messages (`mtype:msg`):**
  - Buyer $\leftrightarrow$ Marketplace: `reserve`, `reserve_ok`, `reserve_fail`, `pay`, `pay_ok`, `pay_fail`, `cancel`, `cancel_ok`, `cancel_fail`, `confirm`, `confirm_ok`, `confirm_fail`.
  - Seller $\leftrightarrow$ Marketplace: `withdraw`, `withdraw_ok`, `withdraw_fail`, `deliver`, `deliver_ok`, `deliver_fail`.
  - Marketplace $\leftrightarrow$ PaymentService: `charge`, `charge_ok`, `charge_fail`, `payout`, `payout_ok`, `refund`, `refund_ok`.

### 2.2 Canonical Channel Signatures
All request/reply channels must carry `res_id` where reservation identity matters:

| Channel | Direction | Signature | Payload Semantics |
| :--- | :--- | :--- | :--- |
| `mkt_req` *(or `to_mkt`)* | Buyers / Seller $\rightarrow$ Marketplace | `chan mkt_req = [4] of { mtype:msg, byte, byte };` | `{ msg_type, sender_id, res_id }` (`NO_RES` for `reserve`/`withdraw`/`deliver`) |
| `buyer_ch[N]` | Marketplace $\rightarrow$ `Buyer(id)` | `chan buyer_ch[N] = [2] of { mtype:msg, byte };` | `{ reply_msg, res_id }` (returns assigned `res_id` on `reserve_ok`) |
| `seller_ch` | Marketplace $\rightarrow$ Seller | `chan seller_ch = [2] of { mtype:msg };` | `{ reply_msg }` |
| `pay_req` *(or `to_pay`)* | Marketplace $\rightarrow$ PaymentService | `chan pay_req = [2] of { mtype:msg, byte, byte };` | `{ cmd, buyer_id, res_id }` |
| `pay_resp` *(or `from_pay`)* | PaymentService $\rightarrow$ Marketplace | `chan pay_resp = [2] of { mtype:msg, byte, byte };` | `{ reply_msg, buyer_id, res_id }` |

### 2.3 Global State & Ghost Variables
- **Core state:** `mtype:state ticket_state = AVAILABLE;`
- **Reservation & ownership tracking:** `byte reserved_by = NO_BUYER;`, `byte current_res_id = NO_RES;`, `byte next_res_id = 1;`, `byte buyer_of_sale = NO_BUYER;`, `byte confirmed_by = NO_BUYER;`
- **Protocol event flags:** `bool deliveryConfirmed = false;`, `bool cancelAccepted = false;`, `bool confirmAccepted = false;`
- **Money ledger (prefer counters over booleans if stale refunds + valid settlements coexist):**
  - `byte charged_cnt = 0;`, `byte held_cnt = 0;`, `byte paidOut_cnt = 0;`, `byte refunded_cnt = 0;`
  - *(Keep boolean aliases or `#define` macros e.g. `#define charged (charged_cnt > 0)` if LTL properties reference booleans.)*

---

## 3. Subagent Brief — M1 (Marketplace & Core State Machine)

- **Role:** Marketplace & Core State Machine
- **Assignee:** Nguyen Quoc Khang (`10423055`)
- **Git Branch:** `feat/marketplace`
- **Owned Scope:** `models/defs.pml` (co-owner with M3), `proctype Marketplace()` in `models/02_final.pml` (and happy-path skeleton for `01_naive.pml`), `init` process startup, Architecture section of the final report.

### 3.1 Required State-Transition Matrix (`Marketplace` in `02_final.pml`)

| Current State | Event / Channel Input | Guard Condition | Atomic State / Ghost Updates & Actions | Next State |
| :--- | :--- | :--- | :--- | :--- |
| `AVAILABLE` | `mkt_req ? reserve(b, _)` | `ticket_state == AVAILABLE` | Assign `current_res_id = next_res_id; next_res_id++` (wrap guard); `reserved_by = b`; `buyer_ch[b] ! reserve_ok(current_res_id)` | `RESERVED` |
| `AVAILABLE` | `mkt_req ? withdraw(_, _)` | `ticket_state == AVAILABLE` | `seller_ch ! withdraw_ok` | `WITHDRAWN` |
| `RESERVED` | `mkt_req ? pay(b, r)` | `b == reserved_by && r == current_res_id` | Forward `pay_req ! charge(b, r)` (stay `RESERVED` until `charge_ok`, or track `charging_in_flight`) | `RESERVED` |
| `RESERVED` | `pay_resp ? charge_ok(b, r)` | `b == reserved_by && r == current_res_id` | `buyer_of_sale = b`; `buyer_ch[b] ! pay_ok(r)` | `PAID` |
| `RESERVED` | `pay_resp ? charge_fail(b, r)` | `b == reserved_by && r == current_res_id` | `buyer_ch[b] ! pay_fail(r)` (remain `RESERVED` or release per proposal) | `RESERVED` |
| `RESERVED` | `mkt_req ? cancel(b, r)` | `b == reserved_by && r == current_res_id` | `cancelAccepted = true`; `reserved_by = NO_BUYER`; `current_res_id = NO_RES`; `buyer_ch[b] ! cancel_ok(r)` | `AVAILABLE` |
| `RESERVED` | Abstract `RESERVED` timeout | `ticket_state == RESERVED` (no in-flight blocking violation) | Release reservation: `reserved_by = NO_BUYER`; `current_res_id = NO_RES` | `AVAILABLE` |
| `AVAILABLE` / other | `pay_resp ? charge_ok(b, r)` *(stale)* | `r != current_res_id \|\| ticket_state != RESERVED` | **Do NOT mutate active sale.** Issue `pay_req ! refund(b, r)` and notify `buyer_ch[b] ! pay_fail(r)` | *(unchanged)* |
| `PAID` | `mkt_req ? deliver(_, _)` | `ticket_state == PAID` | `seller_ch ! deliver_ok` | `DELIVERED` |
| `PAID` | Abstract `PAID` timeout (non-delivery) | `ticket_state == PAID` | Issue `pay_req ! refund(buyer_of_sale, current_res_id)`; await `pay_resp ? refund_ok(_, _)` | `REFUNDED` |
| `DELIVERED` | `mkt_req ? confirm(b, r)` | `b == buyer_of_sale && r == current_res_id` | `deliveryConfirmed = true`; `confirmAccepted = true`; `confirmed_by = b`; issue `pay_req ! payout(b, r)`; await `pay_resp ? payout_ok(_, _)`; `buyer_ch[b] ! confirm_ok(r)` | `SETTLED` |
| *Any* | Unauthorized / wrong-state request | Guard fails (`b != reserved_by` or `r != current_res_id` or wrong state) | Reject without mutating `ticket_state`/`reserved_by`: reply `*_fail` to sender | *(unchanged)* |

### 3.2 Step-by-Step Tasks (Days 1–5)
1. **Day 1 (Hours 1–2 — Barrier 0):** Co-author [`models/defs.pml`](../models/defs.pml) with M3; lock `mtype:state`, `mtype:msg`, channel signatures with `res_id`, and ghost variables. Get M2 and M4 approval.
2. **Day 1 (Hours 3–8 — Barrier 1):** Implement the happy-path `Marketplace()` in `02_final.pml` (`AVAILABLE -> RESERVED -> PAID -> DELIVERED -> SETTLED`) and align `init` process spawning. Verify 0 deadlocks on happy-path simulation with M2 & M3.
3. **Day 2 (Barrier 2):** Add abstract `RESERVED` and `PAID` timeout branches and cooperate with M3 so `01_naive.pml` represents the unguarded baseline (missing `atomic`, missing `res_id`, missing `b == reserved_by`).
4. **Day 3 (Barrier 3):** Harden `Marketplace()` in [`models/02_final.pml`](../models/02_final.pml):
   - Wrap read-check-update transitions in `atomic { ... }` (and pure local variable updates in `d_step { ... }`).
   - Enforce `b == reserved_by && r == current_res_id` on `pay`, `cancel`, and `confirm`.
   - Implement stale-charge handling: if `charge_ok(b, r)` arrives after `RESERVED` timed out or `cancel` succeeded, immediately trigger `pay_req ! refund(b, r)` without overwriting `ticket_state`.
   - Ensure terminal states (`SETTLED`, `WITHDRAWN`, `REFUNDED`) cleanly drain residual channel requests or exit via valid `end:` labels so SPIN reports no invalid end states.
5. **Day 4 (Barrier 4):** Fix any acceptance cycles or deadlocks reported by M4 under `pan -a -f` (e.g., ensure `RESERVED` timeout cannot starve a paying buyer indefinitely if fairness requires progress, or verify non-deterministic progress under A6/A9).
6. **Day 5 (Barrier 5):** Write the **System Architecture & Marketplace State Machine** section of the final report (include the transition table and explain how `atomic` + `res_id` + stale-charge refunds eliminate `S1`, `S5`, `S8`, `S9`).

### 3.3 Acceptance Criteria (Definition of Done)
- [ ] `models/defs.pml` frozen and unchanged after Barrier 0 unless approved by all 4 members.
- [ ] `Marketplace()` rejects every spoofed or stale `pay`/`cancel`/`confirm` without altering `ticket_state` or `buyer_of_sale`.
- [ ] Stale `charge_ok` triggers automatic `refund` and preserves money conservation.
- [ ] Local check passes with 0 deadlocks and 0 assertion errors:
  ```powershell
  spin -p -g -l models/02_final.pml
  spin -a models/02_final.pml
  gcc -O2 -DSAFETY -o pan.exe pan.c
  .\pan.exe
  ```

### 3.4 Pitfalls & Constraints
- **Never put blocking channel sends/receives inside `d_step`:** Use `atomic { ... }` when channel operations are inside the block, and only use `d_step` for deterministic, non-blocking assignments.
- **Do not rely on SPIN's `timeout` keyword for protocol timers** unless you specifically intend "all processes are globally blocked"; model abstract `RESERVED`/`PAID` expirations as guarded non-deterministic transitions (`:: ticket_state == RESERVED -> ...`) so interleavings are explored realistically.
- **Hold `N = 2` and `K = 2` until Day 4:** Do not increase buyer or listing counts during Day 3 safety debugging.

---

## 4. Subagent Brief — M2 (Participants: Seller & Buyer Processes)

- **Role:** Participants (`Seller` and `Buyer(byte id)`)
- **Assignee:** Pham Khac Uy (`10423122`)
- **Git Branch:** `feat/participants`
- **Owned Scope:** `proctype Seller()` and `proctype Buyer(byte id)` in `models/01_naive.pml` and `models/02_final.pml`, Processes & Assumptions section of the final report.

### 4.1 Behavioral Contracts
1. **`Buyer(byte id)` (`id` in `0..N-1`):**
   - **Bounded Retries (`K = 2`):** Loop at most `K` reservation attempts (`byte attempts = 0;`). Send `mkt_req ! reserve(id, NO_RES)` and read reply from `buyer_ch[id] ? msg, r`.
   - **After `reserve_ok(r)`:** Non-deterministically choose one of:
     1. Send `mkt_req ! pay(id, r)` and read `buyer_ch[id] ? msg, _`:
        - If `pay_ok`: wait for either `DELIVERED` (then execute Assumption A9 confirmation) or `REFUNDED` / `SETTLED` termination.
        - If `pay_fail`: retry if `attempts < K` or exit.
     2. Send `mkt_req ! cancel(id, r)` and read `buyer_ch[id] ? cancel_ok/cancel_fail, _`.
     3. **Pre-`PAID` abandonment:** Stop acting while `RESERVED` (simulates buyer walk-away so `Marketplace`'s `RESERVED` timeout can fire).
   - **Spoofed / Unauthorized Request Path (for `S9` testing):** Allow a non-deterministic branch where a non-owning buyer sends `pay(id, r)` / `cancel(id, r)` / `confirm(id, r)` with an arbitrary/stale `r` so `01_naive.pml` triggers an `S9` violation and `02_final.pml` proves rejection.
   - **Post-`DELIVERED` Confirmation (Assumption A9):** Once `ticket_state == DELIVERED && buyer_of_sale == id`, the owning buyer **MUST NOT abandon** and **MUST** send `mkt_req ! confirm(id, my_res_id)` and consume `confirm_ok` from `buyer_ch[id]`.
2. **`Seller()`:**
   - While `ticket_state == AVAILABLE`, non-deterministically choose to **withdraw** (`mkt_req ! withdraw(0, NO_RES)`, read `seller_ch ? _`) or wait for a buyer to pay.
   - While `ticket_state == PAID`, non-deterministically choose between:
     1. **Deliver:** `mkt_req ! deliver(0, NO_RES)`, read `seller_ch ? _`, then terminate once `SETTLED`/`REFUNDED`.
     2. **Non-delivery failure:** Do not send `deliver` (allows `Marketplace`'s `PAID` timeout to trigger `REFUNDED`).
   - Exit cleanly when `ticket_state` reaches any terminal state (`SETTLED`, `WITHDRAWN`, `REFUNDED`).

### 4.2 Step-by-Step Tasks (Days 1–5)
1. **Day 1 (Hours 1–2 — Barrier 0):** Review and sign off on [`models/defs.pml`](../models/defs.pml) channel signatures (`buyer_ch[id]` returning `res_id`, `seller_ch`, `K = 2`).
2. **Day 1 (Hours 3–8 — Barrier 1):** Implement happy-path `Seller()` and `Buyer(byte id)` (`reserve -> reserve_ok -> pay -> pay_ok -> deliver -> confirm -> SETTLED`) and confirm clean termination with M1 & M3.
3. **Day 2 (Barrier 2):** Add all failure & non-deterministic behaviors (`K = 2` retries, `cancel`, pre-`PAID` abandonment, `Seller` `withdraw`, `Seller` non-delivery, and unauthorized/stale request branch for `S9`). Sync these behaviors into `01_naive.pml` with M3.
4. **Day 3 (Barrier 3):** Audit `Buyer(byte id)` and `Seller()` in [`models/02_final.pml`](../models/02_final.pml) to guarantee **Assumption A9** holds on every execution path after `DELIVERED` and that no process leaves unread messages blocking `Marketplace`.
5. **Day 4 (Barrier 4):** Collaborate with M1 and M4 to resolve any liveness acceptance cycles (`L1`–`L3`) caused by buyer/seller polling loops or blocked channels.
6. **Day 5 (Barrier 5):** Write the **Participants (`Seller` & `Buyer`) & Modeling Assumptions (`A1`–`A9`)** section of the final report, explicitly justifying bounded retries `K = 2` and Assumption `A9`.

### 4.3 Acceptance Criteria (Definition of Done)
- [ ] Every `Buyer(id)` executes at most `K = 2` reservation attempts and always terminates on terminal states.
- [ ] Every sent request that expects a reply reads its response from `buyer_ch[id]` or `seller_ch` (no channel overflow deadlocks).
- [ ] Post-`DELIVERED` path strictly enforces Assumption A9 (no abandonment branch after `DELIVERED`).
- [ ] Spoofed/stale request branch exists and cleanly triggers `S9` failure in `01_naive.pml` while being safely rejected in `02_final.pml`.

### 4.4 Pitfalls & Constraints
- **Avoid unbounded busy-wait loops:** Do not write `do :: skip od` polling loops in `Buyer` or `Seller`; guard `do` loops on state conditions or channel reads so SPIN does not generate trivial infinite stuttering cycles that break liveness (`L1`–`L3`).
- **Drain replies before exiting:** If `Buyer` sends a request just as the ticket reaches a terminal state, ensure `Marketplace` and `Buyer` do not deadlock on a full `[2]` channel.
- **No direct edits to `Marketplace()` or `ltl` blocks:** Keep changes scoped to `Seller()` and `Buyer(byte id)`.

---

## 5. Subagent Brief — M3 (Payment Service, LTL Specification & Naive Buggy Model)

- **Role:** Payment Service, LTL Properties & Buggy Baseline Model
- **Assignee:** Truong Thien Nhan (`10423085`)
- **Git Branch:** `feat/payment-ltl`
- **Owned Scope:** `models/defs.pml` (co-owner with M1), `proctype PaymentService()` in `01_naive.pml` & `02_final.pml`, all inline `assert(...)` and `ltl` blocks (`S1`–`S9`, `L1`–`L3`), bug injection in `models/01_naive.pml`, LTL & Counterexamples section of the final report.

### 5.1 `PaymentService` Contract
- Loop reading `pay_req ? cmd, b, r`:
  - **`charge(b, r)`:** Increment `charged_cnt` (or set charge record) only on success; non-deterministically pick:
    - Success: `charged_cnt++; held_cnt++; pay_resp ! charge_ok(b, r)`
    - Failure: `pay_resp ! charge_fail(b, r)`
  - **`payout(b, r)`:** Require `held_cnt > 0`; decrement `held_cnt--`, increment `paidOut_cnt++`, send `pay_resp ! payout_ok(b, r)`.
  - **`refund(b, r)`:** Require `held_cnt > 0`; decrement `held_cnt--`, increment `refunded_cnt++`, send `pay_resp ! refund_ok(b, r)`.
- **Single-disposition ledger invariant:** Every successful charge (`charged_cnt`) is eventually either held (`held_cnt`), paid out (`paidOut_cnt`), or refunded (`refunded_cnt`): `charged_cnt == held_cnt + paidOut_cnt + refunded_cnt`.
- Terminate cleanly when `Marketplace` signals completion or via an `end:` label while waiting on `pay_req`.

### 5.2 `S1`–`S9` & `L1`–`L3` Specification Worklist
*(Confirm exact wording of unverified items against the project proposal in Open Decision #2.)*

| ID | Type | Target / Intent | Draft PROMELA / LTL Structure | Status |
| :--- | :---: | :--- | :--- | :--- |
| **S1** | Safety | No double-sale / single winning buyer | `[] (ticket_state == SETTLED -> buyer_of_sale != NO_BUYER && confirmed_by == buyer_of_sale)` + inline `assert` on sale transition | Draft (verify vs. proposal) |
| **S2** | Safety | `[CONFIRM WITH PROPOSAL]` | Placeholder for proposal safety property S2 | Pending proposal check |
| **S3** | Safety | `[CONFIRM WITH PROPOSAL]` | Placeholder for proposal safety property S3 | Pending proposal check |
| **S4** | Safety | `[CONFIRM WITH PROPOSAL]` | Placeholder for proposal safety property S4 | Pending proposal check |
| **S5** | Safety | Post-payment / cancel-vs-confirm exclusion | `[] !(cancelAccepted && confirmAccepted)` / state transition safety | Draft (verify vs. proposal) |
| **S6** | Safety | `[CONFIRM WITH PROPOSAL]` | Placeholder for proposal safety property S6 | Pending proposal check |
| **S7** | Safety | `[CONFIRM WITH PROPOSAL]` | Placeholder for proposal safety property S7 | Pending proposal check |
| **S8** | Safety | Money conservation & no unrefunded stale charge | `[] (charged_cnt == held_cnt + paidOut_cnt + refunded_cnt)` + terminal `held_cnt == 0` | Draft (verify vs. proposal) |
| **S9** | Safety | Buyer authorization (`reserved_by` / `buyer_of_sale` match) | `[] (confirmAccepted -> confirmed_by == buyer_of_sale)` & no unguarded mutation | Draft (verify vs. proposal) |
| **L1** | Liveness | Reserved/Paid progress under fairness (`A6`, `A9`) | `[] (ticket_state == PAID -> <> (ticket_state == SETTLED \|\| ticket_state == REFUNDED))` | Draft (verify vs. proposal) |
| **L2** | Liveness | Delivery leads to settlement under `A9` | `[] (ticket_state == DELIVERED -> <> (ticket_state == SETTLED))` | Draft (verify vs. proposal) |
| **L3** | Liveness | System eventually reaches a terminal state (`A6`, `A9`) | `<> (ticket_state == SETTLED \|\| ticket_state == WITHDRAWN \|\| ticket_state == REFUNDED)` | Draft (verify vs. proposal) |

### 5.3 Intentional Bug Injection Spec for `models/01_naive.pml`
M3 assembles [`models/01_naive.pml`](../models/01_naive.pml) from the Day 1–2 components and removes hardening guards so SPIN catches concrete concurrency flaws:
1. **Break `S1` (Double-sale / race):** Omit `atomic` around `AVAILABLE -> RESERVED` or `charge_ok -> PAID` check-and-set so two buyers can both reserve or overwrite `buyer_of_sale`.
2. **Break `S5` (Illegal cancel/confirm overlap):** Omit state/ownership guards on `cancel` vs `confirm` or allow `cancel` in `PAID`/`DELIVERED` after `confirm`.
3. **Break `S8` (Stale-charge / money leak):** Drop `r == current_res_id` check on `charge_ok(b, r)` and omit the stale-charge `refund(b, r)` branch so money is charged without being refunded or settled cleanly.
4. **Break `S9` (Missing buyer authorization):** Omit `b == reserved_by` / `b == buyer_of_sale` check on `pay`, `cancel`, or `confirm` so another buyer `id != reserved_by` can hijack the flow.

### 5.4 Step-by-Step Tasks (Days 1–5)
1. **Day 1 (Hours 1–2 — Barrier 0):** Co-author [`models/defs.pml`](../models/defs.pml) with M1; finalize `pay_req`/`pay_resp` layouts and ledger counters/flags.
2. **Day 1 (Hours 3–8 — Barrier 1):** Implement `PaymentService()` happy path (`charge -> charge_ok`, `payout -> payout_ok`) and test `AVAILABLE -> SETTLED` with M1 & M2.
3. **Day 2 (Barrier 2):** Add `charge_fail` and `refund -> refund_ok` to `PaymentService()`; encode all `S1`–`S9` assertions and `ltl` blocks; assemble `01_naive.pml` with the 4 deliberate defects above and hand off to M4 for trail capture.
4. **Day 3 (Barrier 3):** Copy clean `PaymentService()` and finalized `S1`–`S9` + `L1`–`L3` `ltl` blocks into [`models/02_final.pml`](../models/02_final.pml); assist M1/M4 until all `S1`–`S9` pass with 0 errors.
5. **Day 4 (Barrier 4):** Refine `L1`–`L3` predicates if weak fairness (`-a -f`) exposes vacuity or missing fairness preconditions; document every `01_naive.pml` counterexample trace (`S1`, `S5`, `S8`, `S9`) and explain the exact root cause and fix in `02_final.pml`.
6. **Day 5 (Barrier 5):** Finalize the **LTL Specification, Assertions & Counterexample Analysis** section of the report.

### 5.5 Acceptance Criteria (Definition of Done)
- [ ] `PaymentService()` maintains `charged_cnt == held_cnt + paidOut_cnt + refunded_cnt` on every reachable state in `02_final.pml`.
- [ ] All 9 safety (`S1`–`S9`) and 3 liveness (`L1`–`L3`) claims are named in `02_final.pml` as `ltl S1 { ... }` through `ltl L3 { ... }` matching the script's `-N` flags.
- [ ] `01_naive.pml` reliably triggers failures on `S1`, `S5`, `S8`, and `S9` for M4 to capture `.trail` files.

### 5.6 Pitfalls & Constraints
- **LTL globals only:** PROMELA `ltl` blocks cannot reference process-local variables (`Buyer[0]:attempts`); expose everything needed via global/ghost variables and `#define` predicates in `defs.pml` or before the `ltl` blocks.
- **No `X` (next-state) operator:** Never use `X` in `ltl` formulas; it disables SPIN's Partial-Order Reduction (POR) and causes unnecessary state-space blowup.
- **Keep `ltl` names exact:** Ensure `ltl S1`..`S9` and `ltl L1`..`L3` use the exact identifiers consumed by `scripts/run_checks.sh`.

---

## 6. Subagent Brief — M4 (SPIN Verification, Automation, Scalability & Report Lead)

- **Role:** SPIN Verification, Automation, Scalability & Report Lead
- **Assignee:** Vuong Gia Kiet (`10423067`)
- **Git Branch:** `feat/verification`
- **Owned Scope:** [`scripts/run_checks.sh`](../scripts/run_checks.sh), `trails/*.trail`, [`results/`](../results/) (`metrics.csv`), final report compilation & presentation slides.

### 6.1 Required Fixes & Upgrades to `scripts/run_checks.sh`
Review of current [`scripts/run_checks.sh`](../scripts/run_checks.sh) identified 6 concrete items M4 must update:
1. **Critical Bug — Remove `-E` from primary safety/deadlock run (Line 58):**
   - Current line 58 executes `./pan -E`, which tells SPIN to **ignore invalid end states (deadlocks)**. That defeats Barrier 1 ("0 deadlocks") and Barrier 3. Remove `-E` from the deadlock/safety check so `./pan` enforces deadlock freedom.
2. **Automate All Named LTL Properties (`S1`–`S9` and `L1`–`L3`):**
   - Currently the script accepts only one optional `ltl_name` and runs `./pan -a -f` once. Add a mode (e.g. `all` or default loop) that runs `./pan -N S1`..`S9` (compiled with `-DSAFETY`) and `./pan -a -f -N L1`..`L3` (compiled **without** `-DSAFETY`).
3. **Implement `capture_trail()`:**
   - When `pan` reports `errors: >0` for a property `<prop>` on `<model>`, move/copy `<model>.pml.trail` (or `pan.trail`) to `trails/${MODEL_BASE}_${prop}.trail` so it is preserved and tracked by `.gitignore` (`!trails/*.trail`).
4. **Align `results/metrics.csv` Header with Architecture Spec:**
   - Current script writes `timestamp,model,mode,ltl_property,errors,states_stored,transitions,memory_mb,elapsed_sec`.
   - Update to match [`docs/repository_pipeline_architecture.md`](repository_pipeline_architecture.md): `timestamp,model,property,N_buyers,M_listings,flags,errors,states,transitions,memory_MB,runtime_s,result`.
5. **Add Scalability Benchmark Matrix:**
   - Support running across `N = 2, 3, 4` (`-DN=2`, `-DN=3`, `-DN=4`), `M = 1, 2` (if multi-listing is implemented in Day 4), and compiler flags: baseline (`-O2`), `-DCOLLAPSE`, `-DBITSTATE`, and `-DNOREDUCE` (to quantify Partial-Order Reduction savings).
6. **Windows 11 Git Bash Compatibility:**
   - Verify whether `gcc -o pan pan.c` produces `pan.exe` under MinGW/MSYS2 and ensure the script invokes `./pan` cleanly and cleans up `pan*` and `_spin_nvr.tmp` on exit without deleting `trails/*.trail`.

### 6.2 Step-by-Step Tasks (Days 1–5)
1. **Day 1 (Hours 1–2 — Barrier 0):** Verify Windows 11 `spin.exe` + `gcc.exe` + Git Bash setup across the team; review `defs.pml`.
2. **Day 1 (Hours 3–8 — Barrier 1):** Fix `-E` in `run_checks.sh`, add `capture_trail()`, align CSV columns, and validate the team's Day 1 happy-path model (0 deadlocks).
3. **Day 2 (Barrier 2):** Run `run_checks.sh` on `models/01_naive.pml` across `S1`, `S5`, `S8`, `S9`; capture and commit `trails/01_naive_S1.trail`, `01_naive_S5.trail`, `01_naive_S8.trail`, `01_naive_S9.trail`; export readable counterexample logs (`spin -t -p -g -l models/01_naive.pml`) for M3.
4. **Day 3 (Barrier 3):** Run full deadlock + assertion + `S1`–`S9` suite on `models/02_final.pml`; log all runs to `results/metrics.csv`; report any failing traces immediately to M1/M2/M3.
5. **Day 4 (Barrier 4):**
   - Run `L1`, `L2`, `L3` under weak fairness (`./pan -a -f -N L1`, etc.).
   - Execute the scalability study (`N = 2, 3, 4`; baseline vs. `-DCOLLAPSE` vs. `-DBITSTATE` vs. `-DNOREDUCE`; `M = 1, 2` if applicable) and populate `results/metrics.csv`.
6. **Day 5 (Barrier 5):** Compile all team sections into the final report and presentation slides; run one final clean pass of `./scripts/run_checks.sh models/02_final.pml` on `main` and verify `git status` leaves no stray `pan.*` files.

### 6.3 Acceptance Criteria (Definition of Done)
- [ ] `scripts/run_checks.sh` detects deadlocks (does not suppress them with `-E`), checks all `S1`–`S9` and `L1`–`L3` claims, captures trails to `trails/`, and writes structured rows to `results/metrics.csv`.
- [ ] All 4 naive counterexample trails (`S1`, `S5`, `S8`, `S9`) are saved in `trails/` and replay cleanly via:
  ```powershell
  spin -t trails/01_naive_S1.trail -p -g -l models/01_naive.pml
  ```
- [ ] `02_final.pml` passes safety (`S1`–`S9`) and liveness (`L1`–`L3`, `-a -f`) with `errors: 0`.
- [ ] `results/metrics.csv` contains complete metrics (`states`, `transitions`, `memory_MB`, `runtime_s`, `result`) for baseline and scalability runs (`N=2,3,4`, `-DCOLLAPSE`, `-DBITSTATE`, POR comparison).

### 6.4 Pitfalls & Constraints
- **Never compile with `-DSAFETY` when checking `L1`–`L3`:** `-DSAFETY` disables acceptance-cycle detection (`-a -f` will fail or skip liveness). Always recompile `pan.c` without `-DSAFETY` for liveness runs.
- **Watch max search depth:** If SPIN prints `Error: max search depth too small`, re-run `pan` with `-m100000` (or `-m500000`) and record the flag in `metrics.csv`.
- **Inspect `unreached` states:** Check SPIN's `unreached in proctype ...` output after verification; large unreachable blocks usually indicate a dead guard or missing non-deterministic branch.

---

## 7. Daily Integration, Git & Review Protocol (All Members)

1. **Branching & PRs:** Develop strictly on `feat/marketplace`, `feat/participants`, `feat/payment-ltl`, and `feat/verification`. Open PRs into `main`; never force-push `main`.
2. **Main Branch Gate:** Before merging any PR to `main` (starting at Barrier 1), run `./scripts/run_checks.sh` on the target model and verify no temporary `pan*` or `_spin_nvr.tmp` artifacts are staged.
3. **10-Minute Nightly Sync:** At the end of each day (Days 1–5), all 4 members review the corresponding Barrier in Section 1.2 together, confirm green gate output, and paste generated traces/tables directly into the report draft.
4. **Edit Policy for This Document:** This plan is a temporary execution guide. Review Section 0 first, mark edits directly in this file or via PR comments, and once approved, copy confirmed assignments and property definitions into [`docs/cpm_team_plan.md`](cpm_team_plan.md).
