# Repository File & Function Interaction Architecture

**Pipeline:** PROMELA / SPIN Verification Pipeline  
**Scope:** Compile-time includes, PROMELA `proctype`/channel interactions, SPIN verification steps, and artifact outputs.

---

## 1. Repository Layout

```text
.
├── models/
│   ├── defs.pml             # Shared interface & ghost state (M1 & M3 — Day 1 Freeze)
│   ├── 01_naive.pml         # Naive buggy model for counterexample hunting (M3)
│   └── 02_final.pml         # Hardened model passing all safety & liveness checks (M1 & M2)
├── scripts/
│   └── run_checks.sh        # Automated SPIN compilation, checking & benchmarking (M4)
├── trails/
│   └── *.trail              # Saved counterexample traces from 01_naive.pml (M3 & M4)
├── results/
│   └── metrics.csv          # Verification & scalability benchmark logs (M4)
├── docs/                    # Proposal, Work Plan, Final Report (All Members)
└── .gitignore               # Ignores build artifacts; tracks !trails/*.trail (All Members)
```

---

## 2. High-Level Data & Verification Flow

```text
                       +-----------------------------+
                       |       models/defs.pml       |
                       | (Shared Interface & State)  |
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
                  | (on S1/S5/S8/S9 fail)                 | (-> CSV)
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
| `models/01_naive.pml` | `scripts/run_checks.sh` | Passed to `spin -a` to verify and catch bugs |
| `models/02_final.pml` | `scripts/run_checks.sh` | Passed as input `.pml` for full safety, liveness, and scalability checks |
| `scripts/run_checks.sh` | `trails/*.trail` | `capture_trail()` saves counterexample traces on `S1`, `S5`, `S8`, `S9` failures |
| `scripts/run_checks.sh` | `results/metrics.csv` | `log_metrics()` parses SPIN stdout and appends rows to CSV |
| `trails/*.trail` | `docs/` | Counterexample traces embedded into the final report |
| `results/metrics.csv` | `docs/` | SPIN benchmark tables embedded into the final report |

---

## 3. PROMELA Model Components (`models/`)

### 3.1 `models/defs.pml` — Shared Interface & Ghost State
**Owner:** M1 & M3 (Day 1 Freeze)

* **`mtype:state` & `mtype:msg`:**
  * **States:** `AVAILABLE`, `RESERVED`, `PAID`, `DELIVERED`, `SETTLED`, `WITHDRAWN`, `REFUNDED`
  * **Messages:** `reserve`, `pay`, `cancel`, `confirm`, `withdraw`, `deliver`, `charge`, `payout`, `refund`
* **Bounded Channels (Assumption A1):**
  * `to_mkt` (Buyers / Seller $\rightarrow$ Marketplace)
  * `to_pay` / `from_pay` (Marketplace $\leftrightarrow$ PaymentService)
  * `buyer_ch[N]`, `seller_ch`
* **Global State & Ghost Variables (for `S1`–`S9`, `L1`–`L3`):**
  * `state`, `reserved_by`, `res_id`, `buyer_of_sale`, `deliveryConfirmed`, `confirmed_by`, `cancelAccepted`, `confirmAccepted`, `charged`, `held`, `paidOut`, `refunded`

---

### 3.2 `models/01_naive.pml` — Naive Buggy Model
**Owner:** M3 (Buggy)

* **`#include "defs.pml"`:** Imports shared `mtype`, channels, and ghost variables.
* **`proctype Marketplace()` [BUGGY]:** Lacks atomic serialisation, lacks `res_id` check, and lacks `buyer_id` (`b == reserved_by`) authorisation guard.
* **`proctype Seller()` & `Buyer(b)`:** Implements withdraw/deliver and $N$ buyers ($K = 2$ retries) sending `reserve`, `pay`, `cancel`, and `confirm`.
* **`proctype PaymentService()`:** Executes the `charge` / `payout` / `refund` ledger.
* **`init` + `ltl S1..S9, L1..L3`:** Spawns processes with assertions and LTL claims intentionally designed to **FAIL** and expose concurrency bugs.

---

### 3.3 `models/02_final.pml` — Hardened Model
**Owner:** M1 & M2 (Fixed)

* **`#include "defs.pml"`:** Imports shared `mtype`, channels, and ghost variables.
* **`proctype Marketplace()` [HARDENED]:** Uses `atomic`/`d_step` serialisation, `b == reserved_by` checks, stale-charge refund logic, and `RESERVED`/`PAID` timeouts.
* **`proctype Seller()` & `Buyer(b)`:**
  * `Seller`: withdraw, deliver, and non-deterministic non-delivery.
  * `Buyer(b)`: pre-`PAID` abandonment and Assumption A9 confirmation once `DELIVERED`.
* **`proctype PaymentService()`:** Enforces single disposition per charge and ledger invariants.
* **`init` + `ltl S1..S9, L1..L3`:** All 9 safety properties and 3 liveness claims **PASS** (0 errors).

---

## 4. Verification Automation (`scripts/run_checks.sh`)
**Owner:** M4 (Automation)

The SPIN runner script automates the full verification lifecycle in six stages:

1. **`compile_model(file.pml)`**
   * Runs `spin -a <file.pml>` to generate `pan.c`.
   * Compiles via `gcc -O2 -o pan pan.c` (optionally with `-DCOLLAPSE` or `-DBITSTATE`).
2. **`run_safety()`**
   * Runs `./pan` to verify assertions and safety LTL properties (`S1`–`S9`).
   * Checks for deadlocks, `S1` double-sale, `S8` stale charge, and `S9` authorisation violations.
3. **`run_liveness()`**
   * Runs `./pan -a -f -N L1` (followed by `L2` and `L3`).
   * Performs acceptance-cycle search under weak fairness (Assumptions A6 and A9).
4. **`capture_trail()` [on error]**
   * Saves generated `*.trail` files to `trails/<model>_<prop>.trail`.
   * Supports trace replay via `spin -t -p <file.pml>`.
5. **`log_metrics()`**
   * Parses SPIN stdout (states stored, transitions, memory in MB, runtime in seconds).
   * Appends structured results to `results/metrics.csv`.
6. **`run_scalability()`**
   * Loops across $N = 2, 3, 4$ buyers and $M = 1, 2$ listings.
   * Logs state-space growth and compression limits.

---

## 5. Artifacts & Documentation

### 5.1 `trails/*.trail` — Counterexample Traces
**Owner:** M3 & M4

* **Saved Files:** `01_naive_S1.trail`, `S5`, `S8`, `S9` (counterexample traces captured from `01_naive.pml`).
* **Replay Command:**
  ```bash
  spin -t -p models/01_naive.pml
  ```
* **Usage:** Used for debugging, report documentation, and live demo walkthroughs.

### 5.2 `results/metrics.csv` — Verification & Scalability Logs
**Owner:** M4

* **Columns:** `model`, `property`, `N_buyers`, `M_listings`, `flags`, `states`, `transitions`, `memory_MB`, `runtime_s`, `result`
* **Scalability Benchmarks:** Compares baseline verification runs against `-DCOLLAPSE` and `-DBITSTATE`.

### 5.3 `docs/` & `.gitignore` — Reporting & Version Control
**Owner:** All Members

* **`docs/` (Proposal, Work Plan, Final Report):** Embeds counterexample traces from `trails/` and SPIN benchmark tables from `results/metrics.csv`.
* **`.gitignore`:**
  * Ignores temporary build and run artifacts: `pan`, `pan.*`, `*.tmp`, and root-level `*.trail`.
  * Explicitly tracks saved counterexamples: `!trails/*.trail`.