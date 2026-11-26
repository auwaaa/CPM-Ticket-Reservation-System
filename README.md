# Ticket Reservation System in PROMELA and LTL

**Course:** Verification of Concurrent Program Models (CPM) — Group 2

## Overview

This project models and formally verifies a concurrent **Ticket Reservation System** in **PROMELA** using the **SPIN** model checker and **Linear Temporal Logic (LTL)**.

### System Architecture & Model Assumptions
- **Participants:**
  - `1` **Seller**
  - `N >= 2` **Buyers** (each with a unique `buyer_id`)
  - `1` **Marketplace** (central coordinator / state machine)
  - `1` **Payment Service** (atomic integer escrow accounting: `balance[N]`, `escrow`, `seller_bal`; auto-`charge` on `reserve` per FR-6)
- **Lifecycle States (7 states):**
  `AVAILABLE` → `RESERVED` → `PAID` → `DELIVERED` → `SETTLED` (and terminal branches `WITHDRAWN`, `REFUNDED`)
- **Timeout & Confirmation Policy (FR-10, FR-11, Assumption 6):**
  Active timed states have finite abstract timeouts: `res_timeout` (`RESERVED` → `AVAILABLE`), `delivery_timeout` (`PAID` → `REFUNDED`), and `confirm_timeout` (`DELIVERED` → `SETTLED` auto-confirmation alongside explicit buyer `confirm(b, r)`).
- **Authoritative Specification:** See [docs/revised_project_proposal.md](docs/revised_project_proposal.md) (`S1`–`S7` safety, `L1`–`L5` liveness).

---

## 4-Member Role Split

| Member | Role & Ownership | Primary Files |
| :--- | :--- | :--- |
| **M1** | Marketplace process & shared definitions | `models/defs.pml`, Marketplace proctype in `02_final.pml` |
| **M2** | Seller & Buyer processes (`N >= 2` concurrent buyers, `K = 2` attempts) | Seller & Buyer proctypes in `02_final.pml` |
| **M3** | PaymentService process, LTL (`S1`–`S7`, `L1`–`L5`) & naive buggy model | `models/defs.pml`, `01_naive.pml`, PaymentService & `ltl` in `02_final.pml` |
| **M4** | SPIN verification, counterexample trails, scalability & report | `scripts/run_checks.sh`, `trails/`, `results/metrics.csv`, `docs/` |

---

## 5-Day Sprint Git Workflow

1. **Freeze `models/defs.pml` first:** Agree on `mtype` values, channel signatures, integer escrow variables, and ghost variables before parallelizing process implementations.
2. **Keep models separate:**
   - `models/01_naive.pml` — Initial naive model (used to demonstrate concurrency bugs and capture counterexamples for `S1`, `S4`, `S5`, `S7` in `trails/`).
   - `models/02_final.pml` — Corrected model that satisfies all safety (`S1`–`S7`) and liveness (`L1`–`L5`) specifications.
3. **Feature branches only:** Develop on dedicated branches (`feat/marketplace`, `feat/participants`, `feat/payment-ltl`, `feat/verification`) and open PRs into `main`.
4. **Gate `main` with `run_checks.sh`:** Never push or merge directly to `main` without passing `./scripts/run_checks.sh`.

---

## Repository Structure

```text
.
├── models/          # PROMELA models (defs.pml, 01_naive.pml, 02_final.pml)
├── scripts/         # Automation scripts (run_checks.sh)
├── trails/          # Saved SPIN counterexample .trail files from 01_naive.pml
├── results/         # SPIN verification logs and scalability metrics (metrics.csv)
└── docs/            # Project proposal, work plan, report drafts, and diagrams
```

---

## Quick Start (Windows 11)

> **Note:** Ubuntu/WSL is **not** required. SPIN and GCC run natively on Windows 11.

### Prerequisites (Native Windows 11)
1. Download the Windows `spin` binary (`spin.exe`) from [spinroot.com](https://spinroot.com/spin/Binaries/index.html) and add it to your `PATH`.
2. Install GCC via [MSYS2](https://www.msys2.org/) (`pacman -S mingw-w64-ucrt-x86_64-gcc`) or WinLibs/MinGW-w64 and add `gcc.exe` to your `PATH`.
3. *(Optional)* Use **Git Bash** (included with Git for Windows) to run `scripts/run_checks.sh`.

### 1. Random Simulation (PowerShell)
```powershell
spin -p -g -l models/02_final.pml
```

### 2. Safety Verification (PowerShell)
```powershell
spin -a models/02_final.pml
gcc -O2 -DSAFETY -o pan.exe pan.c
.\pan.exe
.\pan.exe -N S1   # Repeat for S1..S7
```

### 3. Liveness Verification (PowerShell, Weak Fairness `-a -f`)
```powershell
spin -a models/02_final.pml
gcc -O2 -o pan.exe pan.c
.\pan.exe -a -f -N L1   # Repeat for L1..L5
```

### 4. Automated Check & Metrics Logging (Git Bash)
```bash
./scripts/run_checks.sh models/02_final.pml
```

### 5. Replay a Saved Counterexample Trail (PowerShell)
```powershell
spin -t trails/<example>.trail -p -g -l models/01_naive.pml
```
