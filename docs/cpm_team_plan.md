# Ticket Reservation System in PROMELA & LTL

**Course:** Verification of Concurrent Program Models · Winter Semester 2026  
**Institution:** Vietnamese-German University, Department of Computer Science and Engineering  
**Group 2:** Vuong Gia Kiet (`10423067`), Truong Thien Nhan (`10423085`), Nguyen Quoc Khang (`10423055`), Pham Khac Uy (`10423122`)  
**Authoritative Specification:** [Revised Project Proposal](revised_project_proposal.md)

---

## 1. Role Division (4 Members)

Work is partitioned by component so all four members can code, verify, and document in parallel across a 5-section sprint without blocking each other.

| Slot | Primary Role | Core Deliverables | Assigned To |
| :--- | :--- | :--- | :--- |
| **M1** | **Marketplace & Core State Machine** | Owns `Marketplace()` and co-owns `defs.pml`; implements serialized command processing (`atomic`/`d_step`), auto-`charge(b, r)` on `reserve(b)` (FR-6), `current_buyer` & `current_res_id` tracking (FR-4), stale `charge_ok` refund routing (FR-9), `charge_fail`/cancel release (FR-8), and all three abstract timeouts (`res_timeout`, `delivery_timeout`, `confirm_timeout` per FR-10/FR-11/Assumption 6). | Khang |
| **M2** | **Participants (Seller & Buyer Processes)** | Implements `Seller()` (`withdraw`, `deliver`, non-deterministic non-delivery) and `Buyer(b)` (unique `buyer_id`, bounded attempts $K = 2$ per FR-12, `reserve(b)`, racing `cancel(b, r)`, silence/abandonment in `RESERVED`, and non-deterministic explicit `confirm(b, r)` vs. silence in `DELIVERED` so both explicit confirmation and `confirm_timeout` are explored). | Uy |
| **M3** | **Payment Service & LTL Specification** | Co-owns `defs.pml`, implements `PaymentService()` with atomic integer escrow accounting (`balance[N]`, `escrow`, `seller_bal`, `B0`) and per-charge `(b, r)` single-settlement tracking (Assumption 7, S6, S7), encodes **S1–S7** (safety) and **L1–L5** (liveness) in PROMELA `ltl` blocks, and maintains the naive buggy model (`01_naive.pml`) for counterexample hunting. | Nhân |
| **M4** | **SPIN Verification, Scalability & Report Lead** | Maintains `run_checks.sh`, runs SPIN safety (`S1`–`S7`) and weak-fairness liveness (`-a -f` for `L1`–`L5`) checks, captures counterexample `.trail` files, executes the scalability study ($N = 2, 3, 4$ buyers, varying $K$, 2-listing extension, `-DCOLLAPSE`/`-DBITSTATE`, partial-order reduction), and compiles the final report and slides. | Kiệt |

---

## 2. TODO List

The team operates on a 5-section sprint anchored by the [Revised Project Proposal](revised_project_proposal.md). Because the revised proposal updates the protocol (auto-`charge` on `reserve`, `confirm_timeout` in `DELIVERED`, integer balance ledger, and `S1`–`S7` / `L1`–`L5`), M1 and M3 perform a fast Barrier 0 v2 resync before M2 and M4 lock integration.

| Section | Focus | Parallel Tasks (Members 1–4) | End-of-Section Gate |
| :---: | :--- | :--- | :--- |
| **1** | **Interface Freeze (v2) & Happy Path** | • **M1 & M3:** Freeze `defs.pml` v2 (`mtype`, channels without `pay`, `current_buyer`/`current_res_id`, `balance[N]`/`escrow`/`seller_bal`, `charge_status[]`).<br>• **M1:** Code `Marketplace()` happy path + auto-`charge(b, r)`.<br>• **M2:** Code `Seller()` & `Buyer(b)` happy path (`reserve` $\rightarrow$ `deliver` $\rightarrow$ `confirm`).<br>• **M3:** Code `PaymentService()` integer escrow ledger.<br>• **M4:** Upgrade `run_checks.sh` (remove `-E`, add `S1`–`S7` & `L1`–`L5` loops). | Clean SPIN simulation from `AVAILABLE` $\rightarrow$ `SETTLED` with 0 deadlocks and `sum(balance) + escrow + seller_bal == B0`. |
| **2** | **Failure Modes & Naive Counterexamples** | • **M1 & M2:** Add non-determinism (failed charge releasing `RESERVED -> AVAILABLE`, racing `cancel`, abandonment, `withdraw`, non-delivery, `res_timeout`/`delivery_timeout`/`confirm_timeout`, $K = 2$ attempts, spoofed/stale requests).<br>• **M3:** Update `01_naive.pml` (missing atomicity, missing `res_id` ABA check, unguarded payout/cancel, missing stale refund) and write **S1–S7** assertions/LTL.<br>• **M4:** Run SPIN on `01_naive.pml` and save `.trail` files. | Reproducible counterexamples saved for **S1, S4, S5, and S7** in `trails/`. |
| **3** | **Hardened Model & Safety Suite** | • **M1:** Harden `Marketplace()` in `02_final.pml` (`d_step` serialisation, `(current_buyer, current_res_id)` guards, `charge_fail` release, stale-charge `refund(b, r)` including inside `end_mkt:`, and `confirm_timeout`).<br>• **M2:** Verify `Buyer(b)` and `Seller()` satisfy FR-3, FR-10, FR-11, FR-12 with no channel deadlocks.<br>• **M3:** Finalise `PaymentService()` per-charge single settlement and **S1–S7** / **L1–L5** LTL formulas.<br>• **M4:** Run full safety suite (**S1–S7**) via `run_checks.sh`. | **S1–S7** and deadlock-freedom pass with 0 errors on `02_final.pml`. |
| **4** | **Liveness & Scalability** | • **M1 & M2:** Fix any acceptance cycles or deadlocks found during liveness checks.<br>• **M3:** Document `01_naive.pml` counterexamples and before/after fixes for the report.<br>• **M4:** Run **L1–L5** under weak fairness (`-a -f`), then run scalability benchmarks ($N = 2, 3, 4$ buyers; varying $K$; $M = 1, 2$ listings; `-DCOLLAPSE` / `-DBITSTATE` / `-DNOREDUCE`). | **L1–L5** pass with 0 errors; SPIN metrics table (states, transitions, memory, runtime) is complete. |
| **5** | **Report, Slides & Submission** | • **All:** Assemble final report sections (**M1:** architecture & state machine, **M2:** processes & assumptions, **M3:** LTL `S1`–`S7`/`L1`–`L5` & counterexamples, **M4:** verification & scalability results).<br>• **M4:** Package final `.pml` files + `run_checks.sh` and run one full clean verification pass. | Report, slides, and verified `.pml` bundle submitted. |

---

## 3. SPIN Workflow Rules

* **Freeze `defs.pml` v2 first:** Lock all `mtype` values, canonical channel signatures—`reserve(b)`, `cancel(b, r)`, `confirm(b, r)`, `withdraw`, `deliver`, `charge(b, r)`/`payout(b, r)`/`refund(b, r)` (no separate `pay` command per FR-6)—state/ghost variables (`ticket_state`, `current_buyer`, `current_res_id`, `deliveryConfirmed`, `sale_count`, `ever_paid`, `ever_delivered`, `stale_refund_pending`), and signed integer escrow accounting (`balance[N]`, `escrow`, `seller_bal`, `charge_status[]`) before recoding process logic.
* **Keep only two main model files:** Stick to `01_naive.pml` (buggy) and `02_final.pml` (hardened) with Option A section markers (`/* === M1/M2/M3 SECTION START/END === */`) to prevent merge conflicts.
* **Hold $K = 2$ and $N = 2$ until Section 4:** Do not scale buyers, vary $K$, or add a 2nd listing until all 12 properties (**S1–S7**, **L1–L5**) pass on the base model; state-space explosion will stall Section 3 debugging.
* **Automate verification with `run_checks.sh`:** M4 compiles `pan.c` once for safety (`-DSAFETY`) and once for liveness (no `-DSAFETY`) and runs every named LTL claim (`S1`–`S7`, `./pan -a -f -N L1`..`L5`), logging states, transitions, memory (MB), and runtime to `results/metrics.csv` automatically.
* **Nightly sync & write as you go:** Work strictly on `feat/marketplace`, `feat/participants`, `feat/payment-ltl`, and `feat/verification` and merge via PRs into `main`. Paste counterexample traces (Section 2) and SPIN tables (Section 4) directly into the report draft so Section 5 is purely editing and polish.

---

## 4. Gates & Deliverable Sign-Off Checklist

| Section | Gate / Deliverable Target | Owner | Status |
| :---: | :--- | :--- | :---: |
| **0** | `defs.pml` v2 frozen for [Revised Project Proposal](revised_project_proposal.md) *(v1 merged on `main`, resync needed for FR-6/FR-11/Assumption 7/`S1`–`S7`/`L1`–`L5`)* | M1, M3 (M2, M4 review) | `[ ]` Resync Pending |
| **1** | Happy-path `AVAILABLE` $\rightarrow$ `RESERVED` (auto-`charge`) $\rightarrow$ `PAID` $\rightarrow$ `DELIVERED` $\rightarrow$ `SETTLED` runs with 0 deadlocks | M1, M2, M3 | `[ ]` Pending |
| **2** | `01_naive.pml` + saved `.trail` counterexamples breaking **S1, S4, S5, S7** | M3 & M4 | `[ ]` Pending |
| **3** | `02_final.pml` passes deadlock-freedom + full safety suite (**S1–S7**) with 0 errors | M1, M3, M4 | `[ ]` Pending |
| **4** | `02_final.pml` passes **L1–L5** (`-a -f`); scalability table ($N=2,3,4$, $K$, 2 listings, compression/POR) complete | M4 (All fix) | `[ ]` Pending |
| **5** | Final report, slides, `run_checks.sh`, and `.pml` bundle verified & submitted | All Members | `[ ]` Pending |
