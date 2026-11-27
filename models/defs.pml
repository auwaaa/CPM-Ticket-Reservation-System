/*
 * defs.pml - Shared definitions, message types, channels, and ghost variables
 * Ticket Reservation System (CPM Group 2)
 *
 * Barrier 0 (v2) Interface — Aligned with docs/revised_project_proposal.md
 * Co-owned by M1 & M3. M1 drafted v2; M3 reviewed it and added the S7 ledger
 * macro, the observer hooks, and the payout_res / violation_bad_withdraw
 * ghosts needed by S3/S4. Pending M2/M4 approval.
 */

#ifndef N
#define N 2         /* Number of concurrent Buyers (N >= 2) */
#endif

#ifndef K
#define K 2         /* Bounded reservation attempts per Buyer (FR-12) */
#endif

#define INIT_BAL   K
#define B0         (N * INIT_BAL)
#define NO_BUYER   255
#define NO_RES     0
#define MAX_RES_ID ((N * K) + 2)

/* Per-charge single-settlement status codes (S6) */
#define CHG_NONE     0
#define CHG_HELD     1
#define CHG_PAID_OUT 2
#define CHG_REFUNDED 3

/* -------------------------------------------------------------------------
 * System States (7 states)
 * ------------------------------------------------------------------------- */
mtype:state = {
    AVAILABLE,
    RESERVED,
    PAID,
    DELIVERED,
    SETTLED,
    WITHDRAWN,
    REFUNDED
};

/* -------------------------------------------------------------------------
 * Protocol Messages & Replies (FR-2, FR-3, FR-6: auto-charge on reserve)
 * ------------------------------------------------------------------------- */
mtype:msg = {
    /* Buyer <-> Marketplace */
    reserve, reserve_ok, reserve_fail,
    cancel, cancel_ok, cancel_fail,
    confirm, confirm_ok, confirm_fail,

    /* Seller <-> Marketplace */
    withdraw, withdraw_ok, withdraw_fail,
    deliver, deliver_ok, deliver_fail,

    /* Marketplace <-> PaymentService */
    charge, charge_ok, charge_fail,
    payout, payout_ok,
    refund, refund_ok
};

/* -------------------------------------------------------------------------
 * Bounded Channels (Assumption 1)
 * ------------------------------------------------------------------------- */
chan mkt_req     = [4] of { mtype:msg, byte, byte }; /* { msg_type, sender_id, res_id } */
chan buyer_ch[N] = [2] of { mtype:msg, byte };       /* { reply_msg, res_id } (1-to-1 replies only) */
chan seller_ch   = [2] of { mtype:msg };             /* { reply_msg } */

chan pay_req     = [2] of { mtype:msg, byte, byte }; /* { cmd, buyer_id, res_id } */
chan pay_resp    = [2] of { mtype:msg, byte, byte }; /* { reply_msg, buyer_id, res_id } */

/* -------------------------------------------------------------------------
 * Global Listing State & Integer Escrow Accounting (FR-1, Assumption 7)
 * ------------------------------------------------------------------------- */
mtype:state ticket_state = AVAILABLE;

byte current_buyer  = NO_BUYER;
byte current_res_id = NO_RES;
byte next_res_id    = 1;
bool deliveryConfirmed = false;

short balance[N] = INIT_BAL;
short escrow     = 0;
short seller_bal = 0;
byte charge_status[MAX_RES_ID];   /* per-reservation settlement state (S6), CHG_* codes */
byte charge_payer[MAX_RES_ID];    /* buyer charged for reservation r (refunds must go back to them) */

#if N == 2
#define SUM_BUYER_BAL  (balance[0] + balance[1])
#define ALL_BAL_NONNEG (balance[0] >= 0 && balance[1] >= 0)
#elif N == 3
#define SUM_BUYER_BAL  (balance[0] + balance[1] + balance[2])
#define ALL_BAL_NONNEG (balance[0] >= 0 && balance[1] >= 0 && balance[2] >= 0)
#elif N == 4
#define SUM_BUYER_BAL  (balance[0] + balance[1] + balance[2] + balance[3])
#define ALL_BAL_NONNEG (balance[0] >= 0 && balance[1] >= 0 && balance[2] >= 0 && balance[3] >= 0)
#else
#error "Unsupported N in defs.pml: add SUM_BUYER_BAL / ALL_BAL_NONNEG branch for this N"
#endif

/* S7 ledger predicate (Assumption 7): money is conserved and nothing is negative.
 * Shared by the `ltl S7` claim and by the inline assert()s in PaymentService. */
#define LEDGER_OK ((SUM_BUYER_BAL + escrow + seller_bal == B0) && ALL_BAL_NONNEG && escrow >= 0 && seller_bal >= 0)

/* -------------------------------------------------------------------------
 * Auxiliary Ghost Variables (for LTL S1-S7 and L1-L5)
 *
 * Ghost (history) variables only RECORD what happened; no process may use
 * them in a guard that changes protocol behaviour. They are updated inside
 * the same d_step as the transition they observe, so every claim sees them
 * consistent with ticket_state. NEVER declare them `hidden`: hidden variables
 * are excluded from the state vector, which would make the claims unsound.
 * ------------------------------------------------------------------------- */
byte sale_count  = 0;              /* S1: # of entries into PAID                       */
byte sale_buyer  = NO_BUYER;       /* S1: (b, r) latched on the first entry into PAID  */
byte sale_res_id = NO_RES;
bool ever_paid          = false;   /* S1, S3: PAID was entered at least once           */
bool ever_delivered     = false;   /* S3, S5, L2: DELIVERED was entered                */
bool delivery_timed_out = false;   /* report/trace aid: PAID -> REFUNDED by timeout     */
byte stale_refund_pending = 0;     /* L4: stale charge_ok seen, refund_ok not yet seen  */
byte payout_res = NO_RES;          /* S4: reservation id the seller was paid for (set by PaymentService) */

/* Violation flags, written only by the observer hooks below (Marketplace)
 * or by PaymentService's settlement guard. A correct model never sets them. */
bool violation_mutex_reserve  = false;  /* S2: reserve granted while not AVAILABLE           */
bool violation_bad_withdraw   = false;  /* S3: withdraw accepted while not AVAILABLE        */
bool violation_stale_accept   = false;  /* S4: charge_ok accepted that was not the active (b, r) */
bool violation_dup_settlement = false;  /* S6: payout/refund of a charge that is not HELD    */

#define is_terminal (ticket_state == SETTLED || ticket_state == WITHDRAWN || ticket_state == REFUNDED)

/* -------------------------------------------------------------------------
 * Observer hooks (M3). Call each one INSIDE the d_step that performs the
 * transition and BEFORE ticket_state / current_* are mutated, so the hook
 * judges the transition against the pre-state. Both 01_naive.pml and
 * 02_final.pml call the same hooks: the two models are measured by the
 * same yardstick and differ only in their protocol logic.
 * ------------------------------------------------------------------------- */
inline OBS_RESERVE_GRANT() {
    violation_mutex_reserve = (violation_mutex_reserve || ticket_state != AVAILABLE || current_buyer != NO_BUYER)
}

inline OBS_WITHDRAW() {
    violation_bad_withdraw = (violation_bad_withdraw || ticket_state != AVAILABLE)
}

inline OBS_CHARGE_ACCEPT(ob, ores) {
    violation_stale_accept = (violation_stale_accept || ticket_state != RESERVED ||
                              ob != current_buyer || ores != current_res_id || ores == NO_RES)
}
