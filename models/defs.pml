/*
 * defs.pml - Shared definitions, message types, channels, and ghost variables
 * Ticket Reservation System (CPM Group 2)
 *
 * NOTE: Freeze this file first before implementing 01_naive.pml and 02_final.pml.
 */

#ifndef N
#define N 2   /* Number of concurrent Buyers (N >= 2) */
#endif

#define NO_BUYER 255

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
 * Channels (TODO: finalize buffer sizes and message field layouts)
 * ------------------------------------------------------------------------- */
chan mkt_req  = [4] of { mtype:msg, byte };       /* { msg, sender_id } */
chan buyer_ch[N] = [2] of { mtype:msg };          /* Replies to Buyer[0..N-1] */
chan seller_ch   = [2] of { mtype:msg };          /* Replies to Seller */

chan pay_req  = [2] of { mtype:msg, byte };       /* Marketplace -> PaymentService */
chan pay_resp = [2] of { mtype:msg, byte };       /* PaymentService -> Marketplace */

/* -------------------------------------------------------------------------
 * Global State & Ghost Variables (for LTL S1-S9 and L1-L3)
 * ------------------------------------------------------------------------- */
mtype:state ticket_state = AVAILABLE;

byte reserved_by    = NO_BUYER;
byte buyer_of_sale  = NO_BUYER;
byte confirmed_by   = NO_BUYER;

bool cancelAccepted  = false;
bool confirmAccepted = false;

bool charged  = false;
bool held     = false;
bool paidOut  = false;
bool refunded = false;
