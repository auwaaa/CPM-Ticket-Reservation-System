/*
 * defs.pml - Shared definitions, message types, channels, and ghost variables
 * Ticket Reservation System (CPM Group 2)
 *
 * STATUS: M1 Barrier 0 proposal — pending M3 co-sign and M2/M4 approval before freeze.
 * NOTE: Freeze this file first before parallelizing process implementations.
 */

#ifndef N
#define N 2         /* Number of concurrent Buyers (N >= 2) */
#endif

#ifndef K
#define K 2         /* Bounded reservation retry limit per Buyer */
#endif

#define NO_BUYER 255
#define NO_RES   0
#define MAX_RES  250 /* Wrap guard for next_res_id (stays within byte 1..250) */

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
 * Protocol Messages & Replies
 * ------------------------------------------------------------------------- */
mtype:msg = {
    /* Buyer <-> Marketplace */
    reserve, reserve_ok, reserve_fail,
    pay, pay_ok, pay_fail,
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
 * Bounded Channels (with res_id tracking)
 * ------------------------------------------------------------------------- */
chan mkt_req     = [4] of { mtype:msg, byte, byte }; /* { msg, sender_id, res_id } */
chan buyer_ch[N] = [2] of { mtype:msg, byte };       /* { reply_msg, res_id } */
chan seller_ch   = [2] of { mtype:msg };             /* { reply_msg } */

chan pay_req  = [2] of { mtype:msg, byte, byte };    /* { cmd, buyer_id, res_id } */
chan pay_resp = [2] of { mtype:msg, byte, byte };    /* { reply_msg, buyer_id, res_id } */

/* -------------------------------------------------------------------------
 * Global State & Ghost Variables (for LTL S1-S9 and L1-L3)
 * ------------------------------------------------------------------------- */
mtype:state ticket_state = AVAILABLE;

byte reserved_by    = NO_BUYER;
byte current_res_id = NO_RES;
byte next_res_id    = 1;
byte buyer_of_sale  = NO_BUYER;
byte confirmed_by   = NO_BUYER;

bool deliveryConfirmed = false;
bool cancelAccepted    = false;
bool confirmAccepted   = false;

/* Money ledger counters (preserve conservation when stale refunds + valid sale coexist) */
byte charged_cnt  = 0;
byte held_cnt     = 0;
byte paidOut_cnt  = 0;
byte refunded_cnt = 0;

/* Boolean macro aliases for LTL compatibility */
#define charged  (charged_cnt > 0)
#define held     (held_cnt > 0)
#define paidOut  (paidOut_cnt > 0)
#define refunded (refunded_cnt > 0)
