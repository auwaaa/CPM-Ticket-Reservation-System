# Repository File & Function Interaction Architecture

**Pipeline:** PROMELA / SPIN Verification Pipeline  
**Specification:** [Revised Project Proposal](revised_project_proposal.md) (`S1`–`S7` Safety, `L1`–`L5` Liveness, FR-1–FR-12, Assumptions 1–7)  
**Scope:** Compile-time includes, PROMELA `proctype`/channel interactions, SPIN verification steps, and artifact outputs.

---

## 1. Repository Layout

```text
.
├── models/
│   ├── defs.pml             # Shared interface, escrow ledger & ghost state (M1 & M3 — Barrier 0)
│   ├── 01_naive.pml         # Naive buggy model for counterexample hunting (M3)
│   └── 02_final.pml         # Hardened model passing S1-S7 & L1-L5 (M1, M2, M3)
├── scripts/
│   └── run_checks.sh        # Automated SPIN compilation, checking & benchmarking (M4)
├── trails/
│   └── *.trail              # Saved counterexample traces from 01_naive.pml (M3 & M4)
├── results/
│   └── metrics.csv          # Verification & scalability benchmark logs (M4)
├── docs/                    # Revised Proposal, Team Plan, Execution Plan, Final Report (All Members)
└── .gitignore               # Ignores build artifacts; tracks !trails/*.trail (All Members)
```

---

## 2. High-Level Data & Verification Flow

```text
                       +-----------------------------+
                       |       models/defs.pml       |
                       | (Shared Interface & Ledger) |
                       +--------------+--------------+
                                      |
                    +-----------------+-----------------+
                    | #include "defs.pml"               | #include "defs.pml"
                    v                                   v
      +---------------------------+       +---------------------------+
      |    models/01_naive.pml    | fix   |    models/02_final.pml    |
      |       (Buggy Model)       |------>|     (Hardened Model)      |
      +-------------+-------------+ bugs  +-------------+-------------+
                    |                                   |
                    | 01_naive.pml -> spin -a           | input .pml
                    +-----------------+-----------------+
                                      |
                                      v
                       +-----------------------------+
                       |    scripts/run_checks.sh    |
                       |        (SPIN Runner)        |
                       +--------------+--------------+
                                      |
                  +-------------------+-------------------+
                  | capture_trail()                       | log_metrics()
                  | (on S1/S4/S5/S7 fail)                 | (-> CSV)
                  v                                       v
      +-----------------------+               +-----------------------+
      |    trails/*.trail     |               |  results/metrics.csv  |
      | (Counterexamples)     |               | (Benchmark Metrics)   |
      +-----------+-----------+               +-----------+-----------+
                  |                                       |
                  | counterexample traces                 | tables
                  +-------------------+-------------------+
                                      |
                                      v
                       +-----------------------------+
                       |      docs/ & .gitignore     |
                       | (Proposal, Plan, Report)    |
                       +-----------------------------+
```

### Interaction Summary

| Source | Target | Interaction / Purpose |
| :--- | :--- | :--- |
| `models/defs.pml` | `models/01_naive.pml` | Compile-time `#include "defs.pml"` |
| `models/defs.pml` | `models/02_final.pml` | Compile-time `#include "defs.pml"` |
| `models/01_naive.pml` | `models/02_final.pml` | Iterative bug fixes and hardening |
| `models/01_naive.pml` | `scripts/run_checks.sh` | Passed to `spin -a` to verify and capture concurrency counterexamples |
| `models/02_final.pml` | `scripts/run_checks.sh` | Passed as input `.pml` for full safety (`S1`–`S7`), liveness (`L1`–`L5`), and scalability checks |
| `scripts/run_checks.sh` | `trails/*.trail` | `capture_trail()` saves counterexample traces on `S1`, `S4`, `S5`, `S7` failures |
| `scripts/run_checks.sh` | `results/metrics.csv` | `log_metrics()` parses SPIN stdout and appends rows to CSV |
| `trails/*.trail` | `docs/` | Counterexample traces embedded into the final report |
| `results/metrics.csv` | `docs/` | SPIN benchmark tables embedded into the final report |

---

## 3. PROMELA Model Components (`models/`)

### 3.1 `models/defs.pml` — Shared Interface, Escrow Ledger & Ghost State
**Owner:** M1 & M3 (Barrier 0 Freeze)

* **Parameters & Constants:**
  * `N` (default `2`, override via `-DN=3`, `-DN=4`), `K` (default `2`, bounded attempts per buyer, FR-12), `INIT_BAL` (`K`), `B0` (`N * INIT_BAL`), `NO_BUYER` (`255`), `NO_RES` (`0`), `MAX_RES_ID` (`(N * K) + 2`).
* **`mtype:state` & `mtype:msg`:**
  * **States (7):** `AVAILABLE`, `RESERVED`, `PAID`, `DELIVERED`, `SETTLED`, `WITHDRAWN`, `REFUNDED`
  * **User Commands & Replies (FR-2, FR-3, FR-6 — no separate `pay` command):**
    * Buyer $\leftrightarrow$ Marketplace: `reserve`, `reserve_ok`, `reserve_fail`, `cancel`, `cancel_ok`, `cancel_fail`, `confirm`, `confirm_ok`, `confirm_fail`
    * Seller $\leftrightarrow$ Marketplace: `withdraw`, `withdraw_ok`, `withdraw_fail`, `deliver`, `deliver_ok`, `deliver_fail`
  * **Payment Service Messages:** `charge`, `charge_ok`, `charge_fail`, `payout`, `payout_ok`, `refund`, `refund_ok`
* **Bounded FIFO Channels (Assumption 1 — canonical names):**
  * `mkt_req` (`[4] of { mtype:msg, byte, byte }`): Buyers / Seller $\rightarrow$ Marketplace (`{ msg, sender_id, res_id }`)
  * `buyer_ch[N]` (`[2] of { mtype:msg, byte }`): Marketplace $\rightarrow$ `Buyer(id)` (`{ reply_msg, res_id }`, 1-to-1 replies to user commands only)
  * `seller_ch` (`[2] of { mtype:msg }`): Marketplace $\rightarrow$ Seller (`{ reply_msg }`)
  * `pay_req` (`[2] of { mtype:msg, byte, byte }`): Marketplace $\rightarrow$ PaymentService (`{ cmd, buyer_id, res_id }`)
  * `pay_resp` (`[2] of { mtype:msg, byte, byte }`): PaymentService $\rightarrow$ Marketplace (`{ reply_msg, buyer_id, res_id }`)
* **Global State, Escrow Accounting & Ghost Variables (for `S1`–`S7`, `L1`–`L5`):**
  * **Core listing state:** `ticket_state`, `current_buyer`, `current_res_id`, `next_res_id`, `deliveryConfirmed`
  * **Integer escrow ledger (Assumption 7, `S7`):** signed `short balance[N]` (initialized to `INIT_BAL`), `short escrow = 0`, `short seller_bal = 0`, plus `byte charge_status[MAX_RES_ID]` (`0=NONE, 1=HELD, 2=PAID_OUT, 3=REFUNDED`) for per-charge single settlement (`S6`)
  * **Ghost audit variables:** `sale_count`, `sale_buyer`, `sale_res_id`, `ever_paid`, `ever_delivered`, `stale_refund_pending`, `dup_settlement_err`, `stale_accept_err`, `unconfirmed_payout_err`, `bad_reserve_err`, `bad_withdraw_err` (or equivalent predicates)

---

### 3.2 `models/01_naive.pml` — Naive Buggy Model
**Owner:** M3 (Buggy Baseline)

* **`#include "defs.pml"`:** Imports shared `mtype`, channels, ledger, and ghost variables.
* **`proctype Marketplace()` [BUGGY]:** Omits atomic serialisation, omits `res_id` check on `charge_ok` (exposing the ABA stale-payment hazard), allows unguarded `confirm`/`payout` without `DELIVERED`, and drops stale `charge_ok` without issuing `refund(b, r)`.
* **`proctype Seller()` & `Buyer(b)`:** Exercises concurrent reservations ($K = 2$), racing `cancel`, withdrawal, non-delivery, and spoofed/stale requests.
* **`proctype PaymentService()`:** Weakened guards (or missing per-charge settlement check / non-atomic transfer) to allow `S6`/`S7` violations alongside `Marketplace` defects.
* **`init` + `ltl S1..S7, L1..L5`:** Intentionally triggers reproducible counterexamples for **`S1`, `S4`, `S5`, and `S7`** (saved to `trails/`).

---

### 3.3 `models/02_final.pml` — Hardened Model
**Owner:** M1 (`Marketplace`, `init`), M2 (`Seller`, `Buyer`), M3 (`PaymentService`, `ltl`) — Option A section markers

* **`#include "defs.pml"`:** Imports shared `mtype`, channels, ledger, and ghost variables.
* **`proctype Marketplace()` [HARDENED]:**
  * Uses `d_step` serialisation for atomic state/ghost updates.
  * Automatically dispatches `pay_req ! charge(b, r)` on `reserve_ok(r)` (FR-6).
  * Releases `RESERVED -> AVAILABLE` on `charge_fail(b, r)`, valid `cancel(b, r)`, or `res_timeout` (FR-8).
  * Routes any stale `charge_ok(b, r)` (wrong state or `(b, r) != (current_buyer, current_res_id)`) immediately to `pay_req ! refund(b, r)` without mutating the listing—including inside `end_mkt:` after terminal states (FR-9, `S4`, `L3`, `L4`).
  * Models `deliver` vs. `delivery_timeout` race in `PAID` (FR-10) and explicit `confirm(b, r)` vs. `confirm_timeout` race in `DELIVERED` (FR-11, Assumption 6).
* **`proctype Seller()` & `Buyer(b)`:**
  * `Seller`: `withdraw` in `AVAILABLE`, `deliver` or non-delivery in `PAID`, exits cleanly on terminal state.
  * `Buyer(b)`: at most $K = 2$ `reserve(b)` attempts (FR-12); after `reserve_ok(r)`, non-deterministically sends `cancel(b, r)` or waits; in `DELIVERED`, non-deterministically sends `confirm(b, r)` or stays silent (exercising `confirm_timeout`); optional spoofed/stale `cancel`/`confirm` branch to prove rejection.
* **`proctype PaymentService()`:** Atomic integer transfers (`balance[b] <-> escrow -> seller_bal`), `balance[b] >= 1` check on `charge`, and `charge_status[r]` single-settlement guard (`S6`, `S7`).
* **`init` + `ltl S1..S7, L1..L5`:** All 7 safety properties and 5 liveness claims **PASS** (0 errors).

---

## 4. Verification Automation (`scripts/run_checks.sh`)
**Owner:** M4 (Automation)

The SPIN runner script automates the full verification lifecycle in six stages:

1. **`compile_model(file.pml)`**
   * Runs `spin -a <file.pml>` to generate `pan.c`.
   * Compiles via `gcc -O2 -DSAFETY -o pan pan.c` for safety checks and `gcc -O2 -o pan pan.c` (without `-DSAFETY`) for liveness checks (optionally with `-DCOLLAPSE`, `-DBITSTATE`, or `-DNOREDUCE`).
2. **`run_safety()`**
   * Runs `./pan` (without `-E`, enforcing deadlock freedom) and `./pan -N S1` through `./pan -N S7`.
   * Verifies `S1` (at-most-once sale), `S2` (reservation mutex), `S3` (withdrawal integrity), `S4` (no stale charge acceptance), `S5` (confirmed delivery before payout), `S6` (single settlement per charge), and `S7` (strict global money conservation).
3. **`run_liveness()`**
   * Runs `./pan -a -f -N L1` through `./pan -a -f -N L5`.
   * Performs acceptance-cycle search under weak fairness (Assumptions 4 and 6).
4. **`capture_trail()` [on error]**
   * Saves generated `*.trail` files to `trails/<model>_<prop>.trail`.
   * Supports trace replay via `spin -t trails/<model>_<prop>.trail -p -g -l <file.pml>`.
5. **`log_metrics()`**
   * Parses SPIN stdout (errors, states stored, transitions, memory in MB, runtime in seconds).
   * Appends structured results to `results/metrics.csv`.
6. **`run_scalability()`**
   * Loops across $N = 2, 3, 4$ buyers (`-DN=`), varying $K$ (`-DK=`), $M = 1, 2$ listings, and `-O2` vs. `-DCOLLAPSE` vs. `-DBITSTATE` vs. `-DNOREDUCE`.
   * Logs state-space growth and compression/POR savings.

---

## 5. Artifacts & Documentation

### 5.1 `trails/*.trail` — Counterexample Traces
**Owner:** M3 & M4

* **Saved Files:** `01_naive_S1.trail`, `01_naive_S4.trail`, `01_naive_S5.trail`, `01_naive_S7.trail` (counterexample traces captured from `01_naive.pml`).
* **Replay Command:**
  ```powershell
  spin -t trails/01_naive_S4.trail -p -g -l models/01_naive.pml
  ```
* **Usage:** Used for debugging, report documentation, and live demo walkthroughs.

### 5.2 `results/metrics.csv` — Verification & Scalability Logs
**Owner:** M4

* **Columns:** `timestamp,model,property,N_buyers,K_retries,M_listings,flags,errors,states,transitions,memory_MB,runtime_s,result`
* **Scalability Benchmarks:** Compares baseline verification runs against `-DCOLLAPSE`, `-DBITSTATE`, and `-DNOREDUCE` (POR impact).

### 5.3 `docs/` & `.gitignore` — Reporting & Version Control
**Owner:** All Members

* **`docs/` (Revised Proposal, Team Plan, Execution Plan, Final Report):** Embeds counterexample traces from `trails/` and SPIN benchmark tables from `results/metrics.csv`.
* **`.gitignore`:**
  * Ignores temporary build and run artifacts: `pan`, `pan.*`, `*.tmp`, and root-level `*.trail`.
  * Explicitly tracks saved counterexamples: `!trails/*.trail`.
