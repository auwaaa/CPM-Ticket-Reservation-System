# M3 Report Section — Payment Service, LTL Specification & Counterexample Analysis

**Author:** Truong Thien Nhan (M3, `10423085`) · **Branch:** `feat/payment-ltl-v2`
**Specification:** [Revised Project Proposal](revised_project_proposal.md), Sections 6–8
**Models:** [`models/defs.pml`](../models/defs.pml), [`models/properties.pml`](../models/properties.pml),
[`models/01_naive.pml`](../models/01_naive.pml), [`models/02_final.pml`](../models/02_final.pml)
**Toolchain:** SPIN 6.5.1, GCC 15.1.0 (MSYS2 UCRT64), Windows 11 · base configuration `N = 2`, `K = 2`

---

## 1. Escrow Ledger: the `PaymentService` Process

The payment service keeps the integer ledger of Assumption 7. Each buyer starts with
`INIT_BAL = K` units (so a buyer can fund all of its `K` attempts), giving
`B0 = N · K = 4` units in the system. A per-reservation record `charge_status[r]`
(`NONE → HELD → PAID_OUT | REFUNDED`) and `charge_payer[r]` support single settlement.

| Command | Guard (hardened model) | Atomic effect (`d_step`) | Reply |
| :--- | :--- | :--- | :--- |
| `charge(b, r)` | `charge_status[r] == NONE && balance[b] ≥ 1` (or a non-deterministic decline) | `balance[b]--; escrow++; charge_status[r] = HELD; charge_payer[r] = b` | `charge_ok(b, r)` / `charge_fail(b, r)` |
| `payout(b, r)` | `charge_status[r] == HELD` | `escrow--; seller_bal++; charge_status[r] = PAID_OUT; payout_res = r` | `payout_ok(b, r)` |
| `refund(b, r)` | `charge_status[r] == HELD && charge_payer[r] == b` | `escrow--; balance[b]++; charge_status[r] = REFUNDED` | `refund_ok(b, r)` |

Design decisions:

* **One `d_step` per ledger mutation.** No process and no never claim can ever observe a
  half-finished transfer, so money conservation (S7) is required to hold in *every* reachable
  state, not just between messages. Each `d_step` also asserts `LEDGER_OK` as a second, always-on line of defence.
* **Reject, never clamp.** A `payout`/`refund` for a charge that is not `HELD` (never charged,
  declined, or already settled) moves no money. It is recorded in the ghost flag
  `violation_dup_settlement`, so S6 turns a protocol error into a readable counterexample
  instead of silently corrupting the ledger.
* **Refunds go back to the payer.** A refund must name the buyer recorded in `charge_payer[r]`,
  so a Marketplace bug can never redirect a refund to the wrong buyer.
* **Non-deterministic gateway.** Every `charge` may be declined, which exercises FR-8(a) and the
  cancel/decline race. Every charge is always answered (Assumption 4).

## 2. Observing the Properties: Ghost Variables and Observer Hooks

Several properties talk about *events* ("a stale `charge_ok` is never *accepted*"), but LTL
only sees *states*. The standard technique is a **history (ghost) variable**: it is updated in the
same atomic step as the event it observes and judges that event against the pre-state. Ghosts
never appear in protocol guards, so they cannot change behaviour.

| Hook (in `defs.pml`) | Called inside | Records | Used by |
| :--- | :--- | :--- | :--- |
| `OBS_RESERVE_GRANT()` | reserve-accept `d_step` | grant while not `AVAILABLE` or with a holder | S2 |
| `OBS_WITHDRAW()` | withdraw-accept `d_step` | withdraw while not `AVAILABLE` | S3 |
| `OBS_CHARGE_ACCEPT(b, r)` | `charge_ok → PAID` `d_step` | `(b, r)` ≠ active `(current_buyer, current_res_id)` in `RESERVED` | S4 |
| PaymentService settlement guard | `payout`/`refund` | settlement of a non-`HELD` charge | S6 |

The **same hooks are called from the same places in both models**, so the naive and the
hardened model are measured by one yardstick. Ghosts are deliberately *not* declared `hidden`:
hidden variables are excluded from the state vector, and a never claim reading them would be unsound.

## 3. LTL Specification (`models/properties.pml`)

All 12 formulas live in one file that both models `#include`. Neither model can drift to a
weaker version of a property. None of the formulas uses the next-time operator `X`, so all are
stutter-invariant and SPIN's partial-order reduction remains sound.

### 3.1 Safety (`[] P`)

| ID | PROMELA `ltl` formula | Reading |
| :--- | :--- | :--- |
| **S1** | `[] ((sale_count <= 1) && (ever_paid -> (current_buyer == sale_buyer && current_res_id == sale_res_id && sale_buyer != NO_BUYER && sale_res_id != NO_RES)))` | PAID entered at most once; the sale's `(b, r)` is frozen afterwards. |
| **S2** | `[] (!violation_mutex_reserve && (ticket_state == RESERVED -> (current_buyer != NO_BUYER && current_res_id != NO_RES)))` | Reservations are only granted from a free `AVAILABLE` listing; `RESERVED` always has one holder. |
| **S3** | `[] (!violation_bad_withdraw && (ticket_state == WITHDRAWN -> (!ever_paid && !ever_delivered && current_buyer == NO_BUYER && [] (ticket_state == WITHDRAWN))))` | Withdraw only from `AVAILABLE`; a withdrawn listing was never sold and stays withdrawn. |
| **S4** | `[] (!violation_stale_accept && (payout_res != NO_RES -> payout_res == sale_res_id))` | No stale `charge_ok` is accepted, and the seller is only paid for the sale's own reservation. |
| **S5** | `[] (seller_bal > 0 -> (ever_delivered && deliveryConfirmed && ticket_state == SETTLED))` | Payout only after delivery **and** confirmation (explicit or `confirm_timeout`). |
| **S6** | `[] (!violation_dup_settlement && seller_bal <= 1)` | No duplicate or unbacked payout/refund; the seller is paid at most once. |
| **S7** | `[] LEDGER_OK` where `LEDGER_OK ≡ Σ balance + escrow + seller_bal == B0 ∧ all ≥ 0` | Strict money conservation in every state. |

### 3.2 Liveness (`[] (P -> <> Q)`, checked under weak fairness)

| ID | PROMELA `ltl` formula | Reading |
| :--- | :--- | :--- |
| **L1** | `[] (ticket_state == RESERVED -> <> (ticket_state == AVAILABLE \|\| ticket_state == PAID))` | Every reservation ends. |
| **L2** | `[] (ticket_state == PAID -> <> (ever_delivered \|\| (ticket_state == REFUNDED && charge_status[sale_res_id] == CHG_REFUNDED)))` | A paid ticket is delivered, or the buyer actually gets the money back. |
| **L3** | `[] (escrow > 0 -> <> (escrow == 0))` | Escrow always drains. |
| **L4** | `[] (stale_refund_pending > 0 -> <> (stale_refund_pending == 0))` | Every late `charge_ok` is refunded. |
| **L5** | `[] (ticket_state == PAID -> <> (ticket_state == SETTLED \|\| ticket_state == REFUNDED))` | A sold ticket always reaches a terminal state. |

**Note on L2.** The execution plan's first suggestion, `[] ((ticket_state == PAID && delivery_timed_out) -> <> ...)`,
is **vacuous** in our model: `delivery_timed_out` is set in the same `d_step` that leaves `PAID`,
so the antecedent can never be true. The formula above uses the plan's alternative form and also
checks that the buyer's charge really reached `REFUNDED`, not merely that the listing changed state.

### 3.3 Non-vacuity

A property that "passes" because its trigger never occurs proves nothing. For the hardened model,
we checked "never X" witness claims for the key scenarios. Each one is **violated**, so X is reachable:
a refund after non-delivery, a settlement with payout, a withdrawal, a pending stale refund, the ABA
situation (stale refund pending while the same buyer holds a newer reservation), two charges held
at once, and a sale after three reservations.

### 3.4 Mutation tests (do the properties have teeth?)

On the hardened model, an observer guarded by a correct guard is false by construction. To show the
properties still detect real faults, single mutations were injected into a copy of `02_final.pml`:

| Mutant | Change | Caught by | Not caught by |
| :--- | :--- | :--- | :--- |
| A | `confirm_timeout` pays out reservation `1` instead of `current_res_id` | **S6** | S1, S4, S5, S7 |
| B | `charge_ok` guard drops `r == current_res_id` (BUG-2 alone) | **S4, S1** | S7 |
| C | Stale `charge_ok` no longer refunded (BUG-5 alone) | **L3, L4** (acceptance cycle, depth 138) | S7, L1, L5 |

Mutant C shows why the proposal needs **both** S7 and L3/L4. Money that is stuck in escrow is still
*counted*, so conservation (S7) holds. Only the liveness properties detect that the buyer never gets it back.

Mutant A is instructive. In this protocol a stale charge is always refunded *before* any payout can
reach the PaymentService (FIFO order on `pay_resp` and `pay_req`), so the wrong payout always targets a
non-`HELD` charge. The hardened PaymentService **rejects** it: no money moves, and S6 reports it. S4's
payout clause therefore only fires against a PaymentService that trusts its caller (the naive one).
The properties are complementary, not redundant.

## 4. Naive Model and Injected Defects (`models/01_naive.pml`)

`01_naive.pml` is identical to `02_final.pml` (same `defs.pml`, same Seller/Buyer, same hooks,
same `properties.pml`) except for five tagged defects. Each defect is a plausible developer mistake:

| Tag | Where | Defect | Breaks |
| :--- | :--- | :--- | :--- |
| BUG-1 | Marketplace, `charge_ok` | Accepted while `RESERVED` **or already `PAID`** ("a duplicate confirmation is harmless"); also overwrites `current_res_id` | **S1** |
| BUG-2 | Marketplace, `charge_ok` | Matched on buyer id only, **not on `res_id`** (the ABA problem) | **S4** (and S1) |
| BUG-3 | Marketplace, `confirm` | Accepted in `PAID` as well as `DELIVERED`, without checking `(b, r)` | **S5** |
| BUG-4 | Marketplace `cancel` + PaymentService | Cancel refunds immediately, before the charge outcome is known; PaymentService refunds/pays out without checking `HELD` and clamps escrow at 0 | **S7** (and S6) |
| BUG-5 | Marketplace, stale `charge_ok` | Dropped silently; no refund is sent | **L3, L4** |

"Missing atomicity" was considered and deliberately **not** used as a defect. The Marketplace is
the single consumer of its channels, so splitting a handler only exposes torn intermediate states
to the never claim. That would be a modelling artefact, not a protocol bug.

## 5. Counterexamples

Trails were produced with a breadth-first verifier (`gcc -DSAFETY -DBFS`), so each one is a
**shortest** counterexample. They are saved in [`trails/`](../trails/) and replay with:

```bash
spin -t -k trails/01_naive_S4.trail -c models/01_naive.pml      # message sequence chart
spin -t -k trails/01_naive_S4.trail -p -g -l models/01_naive.pml  # full step-by-step trace
```

The trail's first line records which claim was violated, so no `-N` is needed on replay.
(For `spin`, unlike `pan`, `-N` means "read a never claim from a file".)

### S7 — money is created (`01_naive_S7.trail`, 37 steps)

```text
Buyer1  -> Mkt : reserve(1)            Mkt -> Buyer1 : reserve_ok(r=1)   Mkt -> Pay : charge(1,1)
Buyer1  -> Mkt : cancel(1,1)
Pay     -> Mkt : charge_fail(1,1)      (gateway declines - no money was taken)
Mkt  (cancel)  : RESERVED -> AVAILABLE, sends refund(1,1)          <- BUG-4a
Pay  (refund)  : charge 1 is not HELD, but balance[1]++ anyway     <- BUG-4b
Final ledger   : balance = [2, 3], escrow = 0, seller_bal = 0  ->  total 5 != B0 = 4
```

### S4 — ABA stale charge accepted (`01_naive_S4.trail`, 43 steps)

```text
Buyer1 -> Mkt : reserve(1)    Mkt : RESERVED (1, r=1), charge(1,1)
Pay    -> Mkt : charge_ok(1,1)                 (in flight)
Mkt           : res_timeout   RESERVED -> AVAILABLE
Buyer1 -> Mkt : reserve(1)    Mkt : RESERVED (1, r=2), charge(1,2)
Mkt  <- Pay   : charge_ok(1,1)  is stale (r=1 != 2) but b matches -> PAID   <- BUG-2
```

The fix in `02_final.pml` is the guard `r == current_res_id`. The stale charge is then refunded (FR-9).

### S1 — the ticket is sold twice (`01_naive_S1.trail`, 53 steps)

The S4 prefix continues: the legitimate `charge_ok(1,2)` now arrives while the listing is already
`PAID` and is accepted again (BUG-1). `sale_count = 2`, `escrow = 2`, and `current_res_id` (2) no
longer matches the recorded sale (1).

### S5 — seller paid without delivery (`01_naive_S5.trail`, 43 steps)

```text
Buyer1 -> Mkt : reserve(1) ... charge_ok(1,1) -> PAID (buyer 1 is the holder)
Buyer0 -> Mkt : confirm(0, 1)        (spoofed: buyer 0 is not the holder)
Mkt           : accepted in PAID, -> SETTLED, payout(1,1)       <- BUG-3
Final         : seller_bal = 1, ever_delivered = false
```

## 6. Verification Results

### 6.1 Hardened model `02_final.pml` (`N = 2`, `K = 2`)

All builds use `-O2 -DCOLLAPSE` and run with `-m1000000`. The maximum depth reached was 275, so no search was truncated.

| Check | Build / run | Result | States stored | Transitions | Memory (MB) | Time (s) |
| :--- | :--- | :---: | ---: | ---: | ---: | ---: |
| Deadlock freedom | `-DSAFETY -DNOCLAIM`, `./pan` | ✅ 0 errors | 12,427,383 | 49,461,822 | 822.6 | 41.4 |
| S1 At-most-once sale | `-DSAFETY`, `-N S1` | ✅ 0 errors | 12,427,383 | 49,466,898 | 822.6 | 56.6 |
| S2 Reservation mutex | `-DSAFETY`, `-N S2` | ✅ 0 errors | 12,427,383 | 49,466,898 | 822.6 | 53.8 |
| S3 Withdrawal integrity | `-DSAFETY`, `-N S3` | ✅ 0 errors | 15,285,736 | 73,420,034 | 931.7 | 64.9 |
| S4 No stale charge acceptance | `-DSAFETY`, `-N S4` | ✅ 0 errors | 12,427,383 | 49,466,898 | 822.6 | 40.8 |
| S5 Confirmed delivery before payout | `-DSAFETY`, `-N S5` | ✅ 0 errors | 12,427,383 | 49,466,898 | 822.6 | 47.7 |
| S6 Single settlement | `-DSAFETY`, `-N S6` | ✅ 0 errors | 12,427,383 | 49,466,898 | 822.6 | 39.2 |
| S7 Money conservation | `-DSAFETY`, `-N S7` | ✅ 0 errors | 12,427,383 | 49,466,898 | 822.6 | 52.3 |
| L1 Reservation termination | `-DNFAIR=3`, `-a -f -N L1` | ✅ 0 errors | 15,885,039 | 91,482,730 | 1,207.3 | 80.3 |
| L2 Non-delivery refund | `-DNFAIR=3`, `-a -f -N L2` | ✅ 0 errors | 14,673,769 | 84,110,705 | 1,142.5 | 84.8 |
| L3 Escrow resolution | `-DNFAIR=3`, `-a -f -N L3` | ✅ 0 errors | 22,656,135 | 473,262,730 | 2,064.0 | 478\* |
| L4 Late-payment refund | `-DNFAIR=3`, `-a -f -N L4` | ✅ 0 errors | 23,212,177 | 402,185,300 | 2,093.5 | 371\* |
| L5 Post-sale termination | `-DNFAIR=3`, `-a -f -N L5` | ✅ 0 errors | 14,081,221 | 70,422,981 | 1,110.9 | 69.5 |

\* Times are wall-clock on a shared 8-core laptop and are **indicative only**: L3/L4 ran while the
naive suite was running in parallel, and an orphaned verifier from an earlier, unreduced attempt
held one core and about 9 GB of RAM throughout. State, transition and memory counts are
deterministic and unaffected. M4 should re-time on an idle machine for the scalability table. The S-runs share
one state space (12.4 M) because a `[] p` claim never branches. S3's nested `[]` doubles part of it.

### 6.2 Naive model `01_naive.pml` (`N = 2`, `K = 2`)

Same builds as above. For violated properties, "states" is what DFS explored before hitting the
error. "BFS depth" is the length of the shortest counterexample (the trail saved in `trails/`).

| Check | Result | States stored | DFS depth | BFS depth | Caused by |
| :--- | :---: | ---: | ---: | ---: | :--- |
| Deadlock freedom | ✅ holds | 38,546,531 | – | – | – |
| **S1** At-most-once sale | ❌ **violated** | 254 | 151 | **53** | BUG-1 + BUG-2 |
| S2 Reservation mutex | ✅ holds | 38,546,531 | – | – | – |
| S3 Withdrawal integrity | ✅ holds | 42,517,862 | – | – | – |
| **S4** No stale charge acceptance | ❌ **violated** | 50 | 126 | **43** | BUG-2 |
| **S5** Confirmed delivery before payout | ❌ **violated** | 2,384 | 195 | **43** | BUG-3 |
| S6 Single settlement | ❌ violated | 60 | 166 | 37 | BUG-4 |
| **S7** Money conservation | ❌ **violated** | 5,019 | 139 | **37** | BUG-4 |
| L1 Reservation termination | ✅ holds | 43,129,511 | – | – | – |
| L2 Non-delivery refund | ❌ violated (acceptance cycle) | 2,741 | 209 | – | BUG-3: a stale/spoofed `confirm` settles a PAID, undelivered listing, so the buyer gets neither ticket nor refund |
| L3 Escrow resolution | ❌ violated (acceptance cycle) | 593 | 153 | – | BUG-5 (isolated by mutant C, §3.4) |
| L4 Late-payment refund | ❌ violated (acceptance cycle) | 82 | 186 | – | BUG-5 (isolated by mutant C, §3.4) |
| L5 Post-sale termination | ✅ holds | 46,261,365 | – | – | timeouts still force termination |

The naive model fails **exactly the four required safety properties (S1, S4, S5, S7)**, plus S6 and
L2–L4 as direct consequences of the same defects. It still satisfies everything the defects do not
touch (S2, S3, L1, L5, deadlock freedom). The naive state space is about 3× larger than the hardened
one because the defects enable extra behaviours (re-entering PAID, payouts from PAID).

Liveness counterexamples on the naive model are not saved in `trails/`: DFS finds long paths where
several defects interact (e.g. the L4 trail combines BUG-1, BUG-2, BUG-4a and BUG-5). The single-bug
mutant C (§3.4) is the clean demonstration for L3/L4.

## 7. Making `N = 2, K = 2` Tractable

The first integrated model did not finish: more than 34 M states and 5 GB after 50 s, still growing.
Even `K = 1` gave 27.4 M states. Each change below was measured in isolation at `K = 1`
(and `K = 2` where it finished):

| Step | Change | `K = 1` states | `K = 2` states |
| :--- | :--- | ---: | ---: |
| 0 | Initial integration | 27,368,622 | > 34 M (aborted) |
| – | Reset dead locals with *separate* statements | 38,840,661 (worse) | – |
| 1 | Marketplace and PaymentService handlers made `atomic` (Assumption 3, FR-2) | 4,650,983 | – |
| 2 | Participants' "decide → send → await reply" made `atomic` | 2,674,355 | – |
| 3 | Buyer reserves only when it sees `AVAILABLE`; spoofs only while another buyer holds the listing | 1,478,263 | > 24 M (aborted) |
| 4 | Dead locals cleared *inside* the atomic handlers | 298,241 | 19,976,231 |
| 5 | No `is_terminal -> break` in participants (they block at their `end` label) | **164,029** | **12,427,383** |

Lessons:

* **Interleaving granularity dominates.** Five processes whose guards read shared globals defeat
  partial-order reduction. `atomic` sequences that match the spec's own atomicity assumptions are
  the most effective reduction.
* **Resetting dead variables only helps inside an atomic block.** Done with separate statements,
  it adds new interleaving points and made things worse (step "–").
* **Pruning must keep the interesting races.** Step 3 removes only requests that can only be
  rejected. The FR-4 race (both buyers see `AVAILABLE`) and the ABA scenario remain reachable (§3.3).

## 8. Notes for M4 (Verification Pipeline)

These were found empirically on SPIN 6.5.1 and affect `scripts/run_checks.sh`:

1. **Any `ltl` block disables deadlock detection.** pan reports
   `invalid end states - (disabled by never claim)`, and the run-time flag `-noclaim` is silently
   ignored. Deadlock freedom must be checked with a separate build: `gcc -DSAFETY -DNOCLAIM`, then `./pan`.
2. **Weak fairness needs `-DNFAIR=3`.** With 6 processes, `./pan -a -f` aborts with
   `too many processes -- current max is 6 procs (-DNFAIR=2)`.
3. **Memory.** `-DCOLLAPSE` keeps every `N = 2, K = 2` run near or below 1.2 GB. Use `-m1000000`
   for the depth limit (the default 10 000 is enough today, but not with headroom for `N = 3`).
4. **Safety LTL works with `-DSAFETY`.** SPIN compiles `[] p`, and even S3's nested `[]`, into
   claims whose violation is an `assert`. The "never claim + accept labels requires -a" warning is generic.
5. **Shortest trails.** Use `gcc -DSAFETY -DBFS` for counterexamples that go into the report.
6. **Trail naming and replay.** `trails/01_naive_<prop>.trail`; replay with
   `spin -t -k <trail> -c|-p -g -l models/01_naive.pml`. A trail is only valid for the exact model
   text that produced it, so regenerate trails whenever `01_naive.pml`, `defs.pml` or `properties.pml` change.
