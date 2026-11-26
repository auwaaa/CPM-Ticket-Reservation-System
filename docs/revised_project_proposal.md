# Project Proposal: Formal Verification of a Ticket Reservation System Using PROMELA and LTL

**Course:** Verification of Concurrent Program Models | Winter 2026 | Revised Specification  
**Group:** Group 2 — Vietnamese-German University (VGU)

| Student Name | Matriculation No. |
| :--- | :--- |
| Vuong Gia Kiet | 10423067 |
| Truong Thien Nhan | 10423085 |
| Nguyen Quoc Khang | 10423055 |
| Pham Khac Uy | 10423122 |

---

## 1. Overview

An online ticket resale platform (similar to Viagogo or StubHub) connects sellers who list tickets with buyers who purchase them, while holding each buyer's payment in escrow until the ticket is delivered. Because the seller, multiple buyers, the marketplace, and the payment service execute as independent asynchronous processes, subtle timing interleavings can trigger critical failures: double-selling a single listing, accepting a late payment from an expired reservation, selling a listing after seller withdrawal, paying out a seller without confirmed delivery, losing or creating money in transit, or leaving reservations and escrow funds permanently stuck. These concurrency defects are notoriously difficult to uncover with conventional sequential testing, making formal model checking with PROMELA and SPIN an ideal methodology.

## 2. Objectives

* **Concurrent Modeling in PROMELA:** Model the complete ticket listing lifecycle, escrow accounting, and asynchronous interactions among the seller, $N$ buyers, marketplace, and payment service.
* **Formal Specification in LTL:** Derive rigorous safety (including strict money conservation across all reachable states) and liveness properties directly from the functional requirements.
* **Iterative Verification & Defect Correction:** Verify initial (primitive) designs in SPIN, document counterexamples for concurrency bugs (e.g., stale-payment races, delivery-vs-timeout races), and refine the protocol until all properties hold.
* **Scalability & Configuration Study:** Systematically evaluate verification scalability across multiple system configurations—varying the number of concurrent buyers ($N = 2, 3, 4, \dots$), bounded reservation attempts per buyer ($K$), and multi-listing extensions—while measuring state-space growth, memory consumption, and verification time.

## 3. Project Plan & Scalability Study

The system is modeled as a network of concurrent PROMELA `proctype`s: one **Seller**, $N$ **Buyers** ($N \ge 2$), one **Marketplace** that owns the listing state and serializes incoming commands, and one **Payment Service** that performs atomic charge, refund, and payout ledger operations. Listing states progress through `AVAILABLE`, `RESERVED`, `PAID`, and `DELIVERED` before terminating in `SETTLED`, `WITHDRAWN`, or `REFUNDED`. Operational failures—failed charges, buyer cancellations or abandonment, seller withdrawal, and seller non-delivery—are modeled as non-deterministic events.

**Scalability Study (Core Deliverable):** Exhaustive verification begins on the base configuration (1 seller, $N = 2$ buyers, 1 listing, bounded reservation attempts $K = 2$). We will then systematically scale the configuration across $N \in \{2, 3, 4\}$ concurrent buyers, vary $K$, and investigate a 2-listing configuration to examine state-space explosion. For each configuration, we will record SPIN's visited states, transitions, memory footprint, and verification runtime, applying standard state-space reduction techniques (`atomic`/`d_step` blocks for internal bookkeeping, partial-order reduction, and `COLLAPSE` compression) where necessary to document practical verification boundaries.

## 4. System Description

The system consists of four active process types communicating over bounded, asynchronous FIFO channels: one Seller, $N$ Buyers ($N \ge 2$, each with a unique `buyer_id` $b$), one Marketplace, and one Payment Service. Each listing has a fixed price of $1$ monetary unit. Figure 1 illustrates the system components and message interfaces; Figure 2 illustrates the listing state machine.

![Figure 1: System Overview — Concurrent Processes, Reservation Identifiers (b, r), and Message Channels](fig1_system_overview.png)
*Figure 1: System Overview — Concurrent Processes, Reservation Identifiers $(b, r)$, and Message Channels*

Listing states are `AVAILABLE` (initial), `RESERVED`, `PAID`, `DELIVERED`, `SETTLED`, `WITHDRAWN`, and `REFUNDED`. Three states are terminal for the listing: `WITHDRAWN` (reachable only from `AVAILABLE` prior to sale), `REFUNDED` (reachable from `PAID` upon delivery deadline expiry), and `SETTLED` (reachable from `DELIVERED` upon buyer confirmation or confirmation window expiry). Once a listing enters `PAID`, it is considered sold and must terminate in one of the two post-`PAID` terminal states (`REFUNDED` or `SETTLED`).

![Figure 2: Listing State Lifecycle and Guarded Transitions](fig2_listing_lifecycle.png)
*Figure 2: Listing State Lifecycle and Guarded Transitions*

## 5. Concurrency Challenges & Justification for Model Checking

Although the Marketplace acts as a central coordinator that processes one message at a time, the overall platform is fundamentally concurrent and asynchronous. Buyers, the Seller, and the Payment Service run independently and exchange messages over buffered channels. Testing the Marketplace as an isolated sequential state machine cannot expose multi-process interleaving bugs. Specifically, formal model checking in SPIN is required to verify the following concurrency hazards:

* **Competing Buyer Requests:** Multiple buyers can issue `reserve(b)` concurrently while the listing is `AVAILABLE`. Different scheduling orders determine which buyer wins, while all losing buyers must receive explicit rejections without corrupting state.
* **Asynchronous Payment Latency & Stale Responses (ABA Problem):** The Payment Service processes `charge(b, r)` concurrently with marketplace timeouts and buyer cancellations. A delayed `charge_ok(b, r)` from an expired reservation can arrive after the listing returned to `AVAILABLE`—or even after the same buyer $b$ created a brand-new reservation $r'$. Without a unique reservation ID $r$, the marketplace could misapply the stale payment to the new reservation.
* **Racing Cancellations, Withdrawals, and Timeouts:** A buyer's `cancel(b, r)` may be in flight simultaneously with `charge_ok(b, r)` or `res_timeout`; a seller's `withdraw` may race with a buyer's `reserve(b)`. Every interleaving must leave the listing and payment ledger consistent.
* **Delivery Report vs. Delivery Deadline Race (in `PAID`):** While in `PAID`, the seller's `deliver` message and the marketplace's `delivery_timeout` can occur concurrently. SPIN must exhaustively explore both processing orders to guarantee that the listing is never simultaneously delivered and refunded.
* **In-Flight Escrow Conservation:** Because charges, refunds, and payouts traverse asynchronous channels, intermediate states exist where funds have been deducted from a buyer before the marketplace receives `charge_ok` or before a late refund completes. Exhaustive state-space exploration verifies that money conservation holds across every intermediate state.

## 6. Functional Requirements

* **FR-1 (Initial State):** A new listing starts in `AVAILABLE` with no active buyer (`current_buyer = NONE`) and no active reservation ID (`current_res_id = 0`).
* **FR-2 (Serialized Processing):** The marketplace processes incoming commands (`reserve`, `withdraw`, `cancel`, `deliver`, `confirm`), payment results (`charge_ok`, `charge_fail`), and timeout events one at a time, completing each state transition before handling the next message.
* **FR-3 (Explicit Replies):** Every user command (`reserve`, `withdraw`, `cancel`, `deliver`, `confirm`) receives an explicit reply (`accepted` or `rejected`) from the marketplace so no sender blocks indefinitely.
* **FR-4 (Reservation & Unique Reservation ID):** A `reserve(b)` request received in `AVAILABLE` succeeds, transitions the listing to `RESERVED`, generates a fresh monotonically increasing reservation ID $r$ (unique across all reservation attempts), records `(current_buyer = b, current_res_id = r)`, and replies `accepted(r)` to buyer $b$. In any other state, `reserve(b)` is rejected. When multiple reserve requests compete, the first processed wins and all others are rejected.
* **FR-5 (Seller Withdrawal):** A `withdraw` request received in `AVAILABLE` moves the listing to `WITHDRAWN` and replies `accepted`. In any other state, `withdraw` is rejected. `WITHDRAWN` is terminal.
* **FR-6 (Charge Initiation & Reservation Timeout):** Upon accepting `reserve(b)` with reservation ID $r$, the marketplace sends `charge(b, r)` to the payment service and enables the reservation timeout (`res_timeout`) for $r$.
* **FR-7 (Charge Acceptance):** If `charge_ok(b, r)` arrives while the listing is in `RESERVED` and matches the active pair (`b == current_buyer && r == current_res_id`), the listing transitions to `PAID`, the payment is committed to the listing's escrow, and the delivery deadline is enabled.
* **FR-8 (Reservation Release & Cancellation):** In `RESERVED`, the listing returns to `AVAILABLE`—invalidating `(current_buyer, current_res_id)`—upon any of: (a) `charge_fail(b, r)` matching the active $(b, r)$, (b) `cancel(b, r)` matching the active $(b, r)$, or (c) `res_timeout` for $r$. Any `cancel(b, r)` whose $(b, r)$ does not match the active reservation (or arrives outside `RESERVED`) is rejected.
* **FR-9 (Stale / Late Payment Handling):** If `charge_ok(b, r)` arrives when the listing is not in `RESERVED`, or when $(b, r)$ does not match the currently active `(current_buyer, current_res_id)` (e.g., due to prior timeout, cancellation, or a newer reservation by the same or another buyer), the marketplace ignores it for listing state transitions and immediately sends `refund(b, r)` to the payment service.
* **FR-10 (Delivery & Delivery-Deadline Race in `PAID`):** In `PAID`, the seller's `deliver` report and `delivery_timeout` may occur concurrently. Because the marketplace serializes events, the first event processed determines the outcome: (a) if `deliver` is processed first, the listing transitions to `DELIVERED`, the seller receives `accepted`, the delivery deadline is disabled, and any subsequent `delivery_timeout` is ignored; (b) if `delivery_timeout` is processed first, the listing transitions to `REFUNDED`, the marketplace sends `refund(current_buyer, current_res_id)` to the payment service, and any subsequent `deliver` message from the seller is explicitly rejected. In SPIN, both interleavings are explored non-deterministically.
* **FR-11 (Delivery Confirmation & Payout in `DELIVERED`):** Delivery is formally considered confirmed in `DELIVERED` when either (a) the active buyer sends an explicit `confirm(b, r)` matching `(current_buyer, current_res_id)`, or (b) the confirmation window expires (`confirm_timeout`), which acts as implicit auto-confirmation. Whichever event is processed first transitions the listing to `SETTLED` and triggers `payout(current_res_id)` to the seller; any subsequent `confirm(b, r)` is rejected (or ignored if already settled).
* **FR-12 (Bounded Buyer Attempts):** Each buyer may attempt at most $K$ reservations (finite bound $K \ge 1$) to guarantee a finite, exhaustively verifiable state space.

> **Design Rationale — Why Reservation ID (`res_id`) Is Required**  
> Relying solely on `buyer_id` fails under the ABA scenario: if Buyer A reserves a ticket (attempt 1), the reservation times out, and Buyer A reserves the same ticket again (attempt 2), a delayed `charge_ok` from attempt 1 carries the exact same `buyer_id` as attempt 2. Assigning a fresh reservation ID $r$ to every reservation attempt ensures that every charge, cancellation, confirmation, and refund is unambiguously bound to a single reservation instance $(b, r)$.

## 7. System Assumptions & Accounting Model

1. **Channel Semantics:** Communication channels are bounded FIFO queues that do not lose, duplicate, or reorder messages.
2. **Failure Scope:** Faults are restricted to the modeled events: failed charge, buyer cancellation/abandonment, seller withdrawal, and seller non-delivery.
3. **Marketplace Atomicity:** The marketplace handles one incoming message or timeout event to completion before reading the next.
4. **Eventual Payment Response:** Every `charge(b, r)` request eventually receives either `charge_ok(b, r)` or `charge_fail(b, r)` from the payment service.
5. **Fixed Scope & No Post-`PAID` Disputes:** Ticket price is fixed at $1$ unit; fees, dynamic pricing, search, user accounts, and cryptographic security are out of scope. Buyer-initiated cancellations or disputes after entering `PAID` are invalid and rejected.
6. **Timeout Semantics:** Each active timed state has a finite timeout (`res_timeout` in `RESERVED`, `delivery_timeout` in `PAID`, `confirm_timeout` in `DELIVERED`). If no competing user/payment event resolves the state first, the corresponding timeout event is enabled and triggers `RESERVED` $\rightarrow$ `AVAILABLE`, `PAID` $\rightarrow$ `REFUNDED`, or `DELIVERED` $\rightarrow$ `SETTLED`, respectively, preventing indefinite blocking.
7. **Atomic Ledger & Escrow Accounting:** To verify strict money conservation across all intermediate states, the payment service maintains integer balances: each buyer $b$ starts with initial balance $B_{\text{init}}[b]$ (total initial funds $B_0 = \sum B_{\text{init}}[b]$), `seller_bal = 0`, and `escrow = 0`. On a successful `charge(b, r)`, the payment service atomically transfers $1$ unit from `balance[b]` to `escrow` and records $(b, r)$ as held. On `refund(b, r)`, it atomically transfers $1$ unit from `escrow` back to `balance[b]` and clears $(b, r)$. On `payout(r)`, it atomically transfers $1$ unit from `escrow` to `seller_bal` and clears $(b, r)$. Funds from a late/stale charge remain counted inside `escrow` until `refund(b, r)` completes.

## 8. Properties for Formal Verification (LTL)

All safety properties must hold in every reachable state (LTL pattern $\square P$), including intermediate states while messages are in flight. Liveness properties ensure eventual progress (LTL pattern $\square(P \rightarrow \diamond Q)$) under weak fairness.

### 8.1 Safety Properties

| ID | Property Name | Formal Specification / Invariant |
| :--- | :--- | :--- |
| **S1** | At-Most-Once Sale | A listing is sold to at most one buyer; `PAID` is entered at most once, and once entered, `(current_buyer, current_res_id)` never changes. |
| **S2** | Mutual Exclusion of Reservations | While a listing is `RESERVED`, no other buyer can reserve it (any competing reserve request is rejected). |
| **S3** | Withdrawal Integrity | Withdrawal occurs only from `AVAILABLE`, and a `WITHDRAWN` listing is never reserved or sold (never enters `PAID`). |
| **S4** | No Stale Charge Acceptance | A `charge_ok(b, r)` whose $(b, r)$ does not match the currently active reservation in `RESERVED` never transitions the listing to `PAID` and is never paid out to the seller. *(Note: funds from a late charge may temporarily reside in `escrow` until refunded; see L4.)* |
| **S5** | Confirmed Delivery Before Payout | The seller is paid (`payout` executed) only after the listing has reached `DELIVERED` and delivery has been confirmed—defined as either explicit buyer confirmation `confirm(b, r)` or expiry of the confirmation window `confirm_timeout` (moving the listing to `SETTLED`). |
| **S6** | Single Settlement per Charge | The payment service executes at most one of `payout` or `refund` for any given held charge $(b, r)$, and only upon an explicit command from the marketplace. No duplicate payouts or refunds occur. |
| **S7** | Strict Money Conservation (Global Invariant) | In every reachable state—including intermediate states during charging, holding, late-payment refunding, and payout—the total money in the system is strictly conserved: $\sum \text{balance}[b] + \text{escrow} + \text{seller\_bal} == B_0$, with all individual balances non-negative (no money is ever created or lost). |

### 8.2 Liveness Properties

| ID | Property Name | Formal Specification / Invariant |
| :--- | :--- | :--- |
| **L1** | Reservation Termination | Every reservation eventually ends: whenever the listing enters `RESERVED`, it eventually leaves `RESERVED` (returning to `AVAILABLE` or advancing to `PAID`). |
| **L2** | Non-Delivery Refund | If the listing is in `PAID` and the seller does not deliver before the delivery deadline, the listing eventually reaches `REFUNDED` and the buyer is refunded. |
| **L3** | Escrow Resolution | Every held charge (whether committed to `PAID` or arriving late for an expired/cancelled reservation) is eventually resolved by either a payout or a refund, so `escrow` eventually returns to $0$. |
| **L4** | Late-Payment Refund | Every stale/late successful charge (`charge_ok(b, r)` not matching the active reservation) eventually triggers a completed `refund(b, r)` returning $1$ unit to buyer $b$. |
| **L5** | Post-Sale Termination | Once a listing enters `PAID`, it eventually reaches a terminal state (`SETTLED` or `REFUNDED`). |