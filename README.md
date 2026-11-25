# Ticket Reservation System in PROMELA and LTL

**Course:** Verification of Concurrent Program Models (CPM) — Group 2

## Overview

This project models and formally verifies a concurrent **Ticket Reservation System** in **PROMELA** using the **SPIN** model checker and **Linear Temporal Logic (LTL)**.

### System Architecture & Model Assumptions
- **Participants:**
  - `1` **Seller**
  - `N >= 2` **Buyers** (each with a unique `buyer_id`)
  - `1` **Marketplace** (central coordinator / state machine)
  - `1` **Payment Service** (handles charging, escrow/holding, payout, and refunds)
- **Lifecycle States (7 states):**
  `AVAILABLE` → `RESERVED` → `PAID` → `DELIVERED` → `SETTLED` (and terminal branches `WITHDRAWN`, `REFUNDED`)
- **Confirmation Policy (Assumption A9):**
  There is no confirmation window timeout; only the winning buyer can confirm delivery under Assumption A9.

---

## 4-Member Role Split

| Member | Role & Ownership | Primary Files |
| :--- | :--- | :--- |
| **M1** | Marketplace process & shared definitions | `models/defs.pml`, Marketplace proctype in `01_naive.pml` / `02_final.pml` |
| **M2** | Seller & Buyer processes (`N >= 2` concurrent buyers) | Seller & Buyer proctypes in `01_naive.pml` / `02_final.pml` |
| **M3** | PaymentService process & LTL properties (`S1`–`S9`, `L1`–`L3`) | PaymentService proctype & `ltl` blocks in `models/` |
| **M4** | SPIN verification, counterexample trails, scalability & report | `scripts/run_checks.sh`, `trails/`, `results/metrics.csv`, `docs/` |

---

## 5-Day Sprint Git Workflow

1. **Freeze `models/defs.pml` first:** Agree on `mtype` values, channel signatures, and ghost variables before parallelizing process implementations.
2. **Keep models separate:**
   - `models/01_naive.pml` — Initial naive model (used to demonstrate concurrency bugs and capture counterexamples in `trails/`).
   - `models/02_final.pml` — Corrected model that satisfies all safety (`S1`–`S9`) and liveness (`L1`–`L3`) specifications.
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

### Prerequisites

Choose **one** of the two setups below on Windows 11:

- **Option A — Native Windows (PowerShell / Git Bash):**
  1. Download the Windows `spin` binary (`spin.exe`) from [spinroot.com](https://spinroot.com/spin/Binaries/index.html) and add it to your `PATH`.
  2. Install GCC via [MSYS2](https://www.msys2.org/) (`pacman -S mingw-w64-ucrt-x86_64-gcc`) or WinLibs/MinGW-w64 and add `gcc.exe` to your `PATH`.
  3. Use **Git Bash** (included with Git for Windows) if you want to run `scripts/run_checks.sh`.
- **Option B — WSL2 (Recommended for `run_checks.sh`):**
  ```powershell
  wsl --install -d Ubuntu
  ```
  Inside the WSL Ubuntu terminal:
  ```bash
  sudo apt-get update && sudo apt-get install -y spin gcc
  ```

### 1. Random Simulation
```powershell
spin -p -g -l models/02_final.pml
```

### 2. Safety Verification (Deadlocks, Assertions, Safety LTL)
In PowerShell:
```powershell
spin -a models/02_final.pml
gcc -O2 -DSAFETY -o pan.exe pan.c
.\pan.exe -E
```
*(In Git Bash or WSL2, use `./pan -E`.)*

### 3. Liveness Verification (Acceptance Cycles with Weak Fairness `-a -f`)
In PowerShell:
```powershell
spin -a models/02_final.pml
gcc -O2 -o pan.exe pan.c
.\pan.exe -a -f -N L1
```

### 4. Automated Check & Metrics Logging (Git Bash or WSL2)
```bash
chmod +x scripts/run_checks.sh
./scripts/run_checks.sh models/02_final.pml
```

### 5. Replay a Saved Counterexample Trail
```powershell
spin -t trails/<example>.trail -p -g -l models/01_naive.pml
```
