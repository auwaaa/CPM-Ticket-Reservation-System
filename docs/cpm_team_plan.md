# Ticket Reservation System in PROMELA & LTL

**Course:** Verification of Concurrent Program Models · Winter Semester 2026  
**Institution:** Vietnamese-German University, Department of Computer Science and Engineering  
**Group 2:** Vuong Gia Kiet (`10423067`), Truong Thien Nhan (`10423085`), Nguyen Quoc Khang (`10423055`), Pham Khac Uy (`10423122`)

---

## 1. Role Division (4 Members)

Work is partitioned by component so all four members can code, verify, and document in parallel across a 5-day sprint without blocking each other.

| Slot | Primary Role | Core Deliverables | Assigned To |
| :--- | :--- | :--- | :--- |
| **M1** | **Marketplace & Core State Machine** | Owns the `Marketplace` process, shared `mtype` and channel definitions (`defs.pml`), atomic serialisation (`atomic`/`d_step`), `reserved_by` & `reservation_id` tracking, `buyer_id` authorisation checks, and abstract timeouts (`RESERVED` and `PAID` deadlines). | TBD |
| **M2** | **Participants (Seller & Buyer Processes)** | Implements `Seller` (withdraw, deliver, non-deterministic non-delivery) and `Buyer(b)` (unique `buyer_id`, bounded retries $K = 2$, pre-`PAID` abandonment, and post-`DELIVERED` confirmation per Assumption A9). | Nhân |
| **M3** | **Payment Service & LTL Specification** | Implements `PaymentService` and money ledger (`charged`, `held`, `paidOut`, `refunded`), translates S1–S9 and L1–L3 into PROMELA assertions and `ltl` blocks, and assembles the naive buggy model (`01_naive.pml`) for counterexample hunting. | TBD |
| **M4** | **SPIN Verification, Scalability & Report Lead** | Maintains `run_checks.sh`, runs SPIN safety and acceptance-cycle (`-a -f`) checks, captures counterexample trails, executes the scalability study (more buyers/listings, `-DCOLLAPSE`/`-DBITSTATE`, partial-order reduction), and compiles the final report and slides. | Kiệt |

---

## 2. TODO List

To finish within 5 days, freeze the shared interface in the first 2 hours of Day 1 and run LTL authoring, SPIN automation, and report drafting in parallel with model development.

| Section | Focus | Parallel Tasks (Members 1–4) | End-of-Day Gate |
| :---: | :--- | :--- | :--- |
| **1** | **Interface Freeze & Happy Path** | • **M1 & M3:** Freeze `defs.pml` (`mtype`, channels, ghost vars) in the first 2 hours.<br>• **M1:** Code `Marketplace` happy path.<br>• **M2:** Code `Seller` & `Buyer(b)` happy path.<br>• **M3:** Code `PaymentService` ledger.<br>• **M4:** Create `run_checks.sh`. | Clean SPIN simulation from `AVAILABLE` $\rightarrow$ `SETTLED` with 0 deadlocks. |
| **2** | **Failure Modes & Naive Counterexamples** | • **M1 & M2:** Add non-determinism (failed charge, pre-`PAID` abandonment, withdrawal, non-delivery, timeouts, $K = 2$ retries).<br>• **M3:** Assemble `01_naive.pml` (no serialisation, no `reservation_id`, no `buyer_id` checks) and write S1–S9 assertions/LTL.<br>• **M4:** Run SPIN on `01_naive.pml` and save `.trail` files. | Reproducible counterexamples saved for S1, S5, S8, and S9. |
| **3** | **Hardened Model & Safety Suite** | • **M1:** Add atomic serialisation, `reserved_by` + `reservation_id` guards, and stale-charge refunds to produce `02_final.pml`.<br>• **M2:** Verify `Buyer(b)` obeys A9 (always confirms once `DELIVERED`).<br>• **M3:** Finalise L1–L3 LTL formulas.<br>• **M4:** Run full safety suite (S1–S9) via `run_checks.sh`. | S1–S9 pass with 0 errors on `02_final.pml`. |
| **4** | **Liveness & Scalability** | • **M1 & M2:** Fix any acceptance cycles or deadlocks found during liveness checks.<br>• **M3:** Document counterexamples and before/after fixes for the report.<br>• **M4:** Run L1–L3 under weak fairness (`-a -f`), then run scalability benchmarks ($N = 2, 3, 4$ buyers; $M = 1, 2$ listings; `-DCOLLAPSE` / `-DBITSTATE`). | L1–L3 pass with 0 errors; SPIN metrics table (states, transitions, memory, runtime) is complete. |
| **5** | **Report, Slides & Submission** | • **All:** Assemble final report sections (**M1:** architecture, **M2:** processes/assumptions, **M3:** LTL & counterexamples, **M4:** verification & scalability results).<br>• **M4:** Package final `.pml` files + `run_checks.sh` and run one full clean verification pass. | Report, slides, and verified `.pml` bundle submitted. |

---

## 3. SPIN Workflow Rules

* **Freeze `defs.pml` in Hour 1–2:** Lock all `mtype` values, channel signatures—`reserve(b)`, `pay(b, r)`, `cancel(b, r)`, `confirm(b, r)`, `withdraw`, `deliver`, `charge`/`payout`/`refund`—and ghost variables (`reserved_by`, `buyer_of_sale`, `cancelAccepted`, `confirmAccepted`, `confirmed_by`) before writing process logic.
* **Keep only two main model files:** Stick to `01_naive.pml` (buggy) and `02_final.pml` (hardened) to save time. Only add an intermediate `02_serialised.pml` if you finish Day 3 ahead of schedule.
* **Hold $K = 2$ and $N = 2$ until Day 4:** Do not scale buyers or add multiple listings until all 12 properties (S1–S9, L1–L3) pass on the base model; state-space explosion will stall Day 3 debugging.
* **Automate verification with `run_checks.sh`:** M4 compiles `pan.c` once and runs every assertion and LTL claim (e.g., `./pan -a -f -N L1`), logging states, transitions, memory (MB), and runtime to a CSV file automatically.
* **10-minute nightly sync & write as you go:** Push to Git each evening to verify the End-of-Day Gate together. Paste counterexample traces (Day 2) and SPIN tables (Day 4) directly into the report draft so Day 5 is purely editing and polish.

---

## 4. Gates & Deliverable Sign-Off Checklist

| Section | Gate / Deliverable Target | Owner | Status |
| :---: | :--- | :--- | :---: |
| **1** | `defs.pml` frozen; happy-path `AVAILABLE` $\rightarrow$ `SETTLED` runs with 0 deadlocks | M1, M2, M3 | `[ ]` Pending |
| **2** | `01_naive.pml` + saved `.trail` counterexamples breaking S1, S5, S8, S9 | M3 & M4 | `[ ]` Pending |
| **3** | `02_final.pml` passes full safety suite (S1–S9) with 0 errors | M1, M3, M4 | `[ ]` Pending |
| **4** | `02_final.pml` passes L1–L3 (`-a -f`, A9); scalability table complete | M4 (All fix) | `[ ]` Pending |
| **5** | Final report, slides, `run_checks.sh`, and `.pml` bundle verified & submitted | All Members | `[ ]` Pending |