/*
 * defs.pml - Shared definitions, message types, channels, and ghost variables
 * Ticket Reservation System (CPM Group 2)
 *
 * Barrier 0 (v2) Interface — Aligned with docs/revised_project_proposal.md
 * Co-owned by M1 & M3; pending M3 v2 sync and M2/M4 approval.
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
byte charge_status[MAX_RES_ID];

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

/* -------------------------------------------------------------------------
 * Auxiliary Ghost Variables (for LTL S1-S7 and L1-L5)
 * ------------------------------------------------------------------------- */
byte sale_count  = 0;
byte sale_buyer  = NO_BUYER;
byte sale_res_id = NO_RES;
bool ever_paid          = false;
bool ever_delivered     = false;
bool delivery_timed_out = false;
byte stale_refund_pending = 0;

bool violation_mutex_reserve  = false;
bool violation_stale_accept   = false;
bool violation_dup_settlement = false;

#define is_terminal (ticket_state == SETTLED || ticket_state == WITHDRAWN || ticket_state == REFUNDED)
