/*
 * 03_two_listings.pml - Multi-listing scalability model (M = 2 listings)
 * Ticket Reservation System (CPM Group 2) — Author: Pham Khac Uy (M2)
 *
 * Extends the hardened 02_final.pml protocol to M = 2 concurrent listings
 * sharing ONE Marketplace coordinator, ONE PaymentService, and ONE global
 * escrow ledger. Used in the Section 4 Scalability Study to measure state-space
 * growth and verify cross-listing isolation and money conservation.
 *
 * Build & run examples:
 *   spin -a models/03_two_listings.pml
 *   gcc -O2 -DSAFETY -DNOCLAIM -DCOLLAPSE -DK=1 -o pan pan.c && ./pan
 *   gcc -O2 -DSAFETY -DBITSTATE -o pan pan.c && ./pan -N S7
 *   gcc -O2 -DBITSTATE -DNFAIR=3 -o pan pan.c && ./pan -a -f -N L3
 */

#ifndef M
#define M 2         /* Number of concurrent listings */
#endif

#ifndef N
#define N 2         /* Number of concurrent Buyers (N >= 2) */
#endif

#ifndef K
#define K 2         /* Bounded total reservation attempts per Buyer */
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

/* System states & protocol messages (matching defs.pml v2) */
mtype:state = {
    AVAILABLE, RESERVED, PAID, DELIVERED, SETTLED, WITHDRAWN, REFUNDED
};

mtype:msg = {
    reserve, reserve_ok, reserve_fail,
    cancel, cancel_ok, cancel_fail,
    confirm, confirm_ok, confirm_fail,
    withdraw, withdraw_ok, withdraw_fail,
    deliver, deliver_ok, deliver_fail,
    charge, charge_ok, charge_fail,
    payout, payout_ok,
    refund, refund_ok
};

/* Bounded FIFO channels carrying listing_id l in {0..M-1} */
chan mkt_req      = [8] of { mtype:msg, byte, byte, byte }; /* { msg, l, sender, res_id } */
chan buyer_ch[N]  = [2] of { mtype:msg, byte };             /* { reply_msg, res_id } */
chan seller_ch[M] = [2] of { mtype:msg };                   /* { reply_msg } */
chan pay_req      = [4] of { mtype:msg, byte, byte, byte }; /* { cmd, l, buyer, res_id } */
chan pay_resp     = [4] of { mtype:msg, byte, byte, byte }; /* { reply, l, buyer, res_id } */

/* Per-listing state */
mtype:state ticket_state[M] = AVAILABLE;
byte current_buyer[M]  = NO_BUYER;
byte current_res_id[M] = NO_RES;
bool deliveryConfirmed[M] = false;

byte next_res_id = 1;  /* Global monotonically increasing reservation_id */

/* Shared integer escrow accounting */
short balance[N]   = INIT_BAL;
short escrow       = 0;
short seller_bal[M] = 0;
byte charge_status[MAX_RES_ID];
byte charge_payer[MAX_RES_ID];
byte charge_listing[MAX_RES_ID];

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
#error "Unsupported N in 03_two_listings.pml"
#endif

#if M == 2
#define SUM_SELLER_BAL  (seller_bal[0] + seller_bal[1])
#define ALL_SELLER_NONNEG (seller_bal[0] >= 0 && seller_bal[1] >= 0)
#define is_terminal(l) (ticket_state[l] == SETTLED || ticket_state[l] == WITHDRAWN || ticket_state[l] == REFUNDED)
#define all_terminal   (is_terminal(0) && is_terminal(1))
#else
#error "03_two_listings.pml expects M == 2"
#endif

#define LEDGER_OK ((SUM_BUYER_BAL + escrow + SUM_SELLER_BAL == B0) && ALL_BAL_NONNEG && escrow >= 0 && ALL_SELLER_NONNEG)

/* Per-listing ghost variables */
byte sale_count[M]     = 0;
byte sale_buyer[M]     = NO_BUYER;
byte sale_res_id[M]    = NO_RES;
bool ever_paid[M]      = false;
bool ever_delivered[M] = false;
byte payout_res[M]     = NO_RES;
byte stale_refund_pending = 0;

bool violation_mutex_reserve  = false;
bool violation_bad_withdraw   = false;
bool violation_stale_accept   = false;
bool violation_dup_settlement = false;
bool violation_cross_listing  = false;

inline OBS_RESERVE_GRANT(ol) {
    violation_mutex_reserve = (violation_mutex_reserve || ticket_state[ol] != AVAILABLE || current_buyer[ol] != NO_BUYER)
}

inline OBS_WITHDRAW(ol) {
    violation_bad_withdraw = (violation_bad_withdraw || ticket_state[ol] != AVAILABLE)
}

inline OBS_CHARGE_ACCEPT(ol, ob, ores) {
    violation_stale_accept = (violation_stale_accept || ticket_state[ol] != RESERVED ||
                              ob != current_buyer[ol] || ores != current_res_id[ol] || ores == NO_RES)
}

/* === Marketplace (coordinates both listings 0 and 1) === */
proctype Marketplace() {
    mtype:msg msg;
    byte l, b, r, assigned_r;

end_active:
    do
    :: all_terminal ->
        break

    :: atomic { (nfull(pay_req) && nempty(mkt_req)) ->
        mkt_req ? msg, l, b, r;
        if
        :: (l >= M) ->
            skip
        :: (msg == reserve) ->
            if
            :: (ticket_state[l] == AVAILABLE && b < N && next_res_id < MAX_RES_ID) ->
                d_step {
                    OBS_RESERVE_GRANT(l);
                    assigned_r = next_res_id;
                    current_res_id[l] = assigned_r;
                    next_res_id++;
                    current_buyer[l] = b;
                    ticket_state[l] = RESERVED
                };
                buyer_ch[b] ! reserve_ok(assigned_r);
                pay_req ! charge(l, b, assigned_r)
            :: else ->
                if
                :: (b < N) -> buyer_ch[b] ! reserve_fail(NO_RES)
                :: else -> skip
                fi
            fi

        :: (msg == withdraw) ->
            if
            :: (ticket_state[l] == AVAILABLE) ->
                d_step {
                    OBS_WITHDRAW(l);
                    ticket_state[l] = WITHDRAWN
                };
                seller_ch[l] ! withdraw_ok
            :: else ->
                seller_ch[l] ! withdraw_fail
            fi

        :: (msg == cancel) ->
            if
            :: (ticket_state[l] == RESERVED && b == current_buyer[l] && r == current_res_id[l] && r != NO_RES && b < N) ->
                d_step {
                    current_buyer[l] = NO_BUYER;
                    current_res_id[l] = NO_RES;
                    ticket_state[l] = AVAILABLE
                };
                buyer_ch[b] ! cancel_ok(r)
            :: else ->
                if
                :: (b < N) -> buyer_ch[b] ! cancel_fail(r)
                :: else -> skip
                fi
            fi

        :: (msg == deliver) ->
            if
            :: (ticket_state[l] == PAID) ->
                d_step {
                    ever_delivered[l] = true;
                    ticket_state[l] = DELIVERED
                };
                seller_ch[l] ! deliver_ok
            :: else ->
                seller_ch[l] ! deliver_fail
            fi

        :: (msg == confirm) ->
            if
            :: (ticket_state[l] == DELIVERED && b == current_buyer[l] && r == current_res_id[l] && r != NO_RES && b < N) ->
                d_step {
                    deliveryConfirmed[l] = true;
                    ticket_state[l] = SETTLED
                };
                pay_req ! payout(l, b, r);
                buyer_ch[b] ! confirm_ok(r)
            :: else ->
                if
                :: (b < N) -> buyer_ch[b] ! confirm_fail(r)
                :: else -> skip
                fi
            fi

        :: else -> skip
        fi;
        msg = 0; l = 0; b = 0; r = 0; assigned_r = 0
       }

    :: atomic { pay_resp ? msg, l, b, r ->
        if
        :: (l >= M) ->
            skip
        :: (msg == charge_ok) ->
            if
            :: (ticket_state[l] == RESERVED && b == current_buyer[l] && r == current_res_id[l] && r != NO_RES) ->
                d_step {
                    OBS_CHARGE_ACCEPT(l, b, r);
                    ever_paid[l] = true;
                    sale_count[l]++;
                    sale_buyer[l] = b;
                    sale_res_id[l] = r;
                    ticket_state[l] = PAID
                }
            :: else ->
                d_step { stale_refund_pending++ };
                pay_req ! refund(l, b, r)
            fi

        :: (msg == charge_fail) ->
            if
            :: (ticket_state[l] == RESERVED && b == current_buyer[l] && r == current_res_id[l] && r != NO_RES) ->
                d_step {
                    current_buyer[l] = NO_BUYER;
                    current_res_id[l] = NO_RES;
                    ticket_state[l] = AVAILABLE
                }
            :: else -> skip
            fi

        :: (msg == refund_ok) ->
            if
            :: (r != sale_res_id[l]) ->
                d_step {
                    if
                    :: (stale_refund_pending > 0) -> stale_refund_pending--
                    :: else -> skip
                    fi
                }
            :: else -> skip
            fi

        :: else -> skip
        fi;
        msg = 0; l = 0; b = 0; r = 0
       }

    /* Abstract timeouts for listing 0 and listing 1 */
    :: d_step {
        (ticket_state[0] == RESERVED) ->
        current_buyer[0] = NO_BUYER;
        current_res_id[0] = NO_RES;
        ticket_state[0] = AVAILABLE
       }
    :: d_step {
        (ticket_state[1] == RESERVED) ->
        current_buyer[1] = NO_BUYER;
        current_res_id[1] = NO_RES;
        ticket_state[1] = AVAILABLE
       }

    :: atomic { (ticket_state[0] == PAID && nfull(pay_req)) ->
        ticket_state[0] = REFUNDED;
        pay_req ! refund(0, current_buyer[0], current_res_id[0])
       }
    :: atomic { (ticket_state[1] == PAID && nfull(pay_req)) ->
        ticket_state[1] = REFUNDED;
        pay_req ! refund(1, current_buyer[1], current_res_id[1])
       }

    :: atomic { (ticket_state[0] == DELIVERED && nfull(pay_req)) ->
        d_step {
            deliveryConfirmed[0] = true;
            ticket_state[0] = SETTLED
        };
        pay_req ! payout(0, current_buyer[0], current_res_id[0])
       }
    :: atomic { (ticket_state[1] == DELIVERED && nfull(pay_req)) ->
        d_step {
            deliveryConfirmed[1] = true;
            ticket_state[1] = SETTLED
        };
        pay_req ! payout(1, current_buyer[1], current_res_id[1])
       }
    od;

end_mkt:
    do
    :: atomic { mkt_req ? msg, l, b, r ->
        if
        :: (l < M) ->
            if
            :: (msg == reserve && b < N) -> buyer_ch[b] ! reserve_fail(NO_RES)
            :: (msg == cancel && b < N)  -> buyer_ch[b] ! cancel_fail(r)
            :: (msg == confirm && b < N) -> buyer_ch[b] ! confirm_fail(r)
            :: (msg == withdraw)         -> seller_ch[l] ! withdraw_fail
            :: (msg == deliver)          -> seller_ch[l] ! deliver_fail
            :: else -> skip
            fi
        :: else -> skip
        fi;
        msg = 0; l = 0; b = 0; r = 0
       }

    :: atomic { pay_resp ? msg, l, b, r ->
        if
        :: (msg == charge_ok && l < M) ->
            d_step { stale_refund_pending++ };
            pay_req ! refund(l, b, r)
        :: (msg == refund_ok && l < M) ->
            if
            :: (r != sale_res_id[l]) ->
                d_step {
                    if
                    :: (stale_refund_pending > 0) -> stale_refund_pending--
                    :: else -> skip
                    fi
                }
            :: else -> skip
            fi
        :: else -> skip
        fi;
        msg = 0; l = 0; b = 0; r = 0
       }
    od
}

/* === Participants: Seller(l) and Buyer(id) === */
proctype Seller(byte l) {
    mtype:msg reply;
    bool withdraw_tried  = false;
    bool deliver_decided = false;

end_seller:
    do
    :: atomic { (ticket_state[l] == AVAILABLE && !withdraw_tried) ->
        withdraw_tried = true;
        mkt_req ! withdraw(l, l, NO_RES);
        seller_ch[l] ? reply;
        reply = 0
       }

    :: atomic { (ticket_state[l] == PAID && !deliver_decided) ->
        deliver_decided = true;
        if
        :: mkt_req ! deliver(l, l, NO_RES);
           seller_ch[l] ? reply;
           reply = 0
        :: skip
        fi
       }
    od
}

proctype Buyer(byte id) {
    mtype:msg reply;
    byte attempts = 0;
    byte my_res[M] = NO_RES;
    byte tmp_r = NO_RES;
    byte l = 0;
    bool confirm_decided[M] = false;
    bool spoofed = false;

end_buyer:
    do
    /* Attempt to reserve listing 0 or listing 1 (up to K attempts total) */
    :: atomic { (attempts < K && (ticket_state[0] == AVAILABLE || ticket_state[1] == AVAILABLE)) ->
        if
        :: (ticket_state[0] == AVAILABLE) -> l = 0
        :: (ticket_state[1] == AVAILABLE) -> l = 1
        fi;
        attempts++;
        mkt_req ! reserve(l, id, NO_RES);
        buyer_ch[id] ? reply, tmp_r;
        if
        :: reply == reserve_ok ->
            my_res[l] = tmp_r;
            if
            :: mkt_req ! cancel(l, id, my_res[l]);
               buyer_ch[id] ? reply, tmp_r
            :: skip
            fi
        :: else -> skip
        fi;
        reply = 0; tmp_r = 0; l = 0
       }

    /* Confirm delivery on listing 0 or 1 when winning buyer */
    :: atomic { (ticket_state[0] == DELIVERED && current_buyer[0] == id && !confirm_decided[0]) ->
        confirm_decided[0] = true;
        if
        :: mkt_req ! confirm(0, id, my_res[0]);
           buyer_ch[id] ? reply, tmp_r
        :: skip
        fi;
        reply = 0; tmp_r = 0
       }
    :: atomic { (ticket_state[1] == DELIVERED && current_buyer[1] == id && !confirm_decided[1]) ->
        confirm_decided[1] = true;
        if
        :: mkt_req ! confirm(1, id, my_res[1]);
           buyer_ch[id] ? reply, tmp_r
        :: skip
        fi;
        reply = 0; tmp_r = 0
       }

    /* Spoofed / stale request against another holder (at most once per buyer) */
    :: atomic { (!spoofed && ((current_buyer[0] != id && current_buyer[0] != NO_BUYER && !is_terminal(0)) ||
                              (current_buyer[1] != id && current_buyer[1] != NO_BUYER && !is_terminal(1)))) ->
        spoofed = true;
        if
        :: (current_buyer[0] != id && current_buyer[0] != NO_BUYER && !is_terminal(0)) -> l = 0
        :: (current_buyer[1] != id && current_buyer[1] != NO_BUYER && !is_terminal(1)) -> l = 1
        fi;
        if
        :: mkt_req ! cancel(l, id, 1);  buyer_ch[id] ? reply, tmp_r
        :: mkt_req ! confirm(l, id, 1); buyer_ch[id] ? reply, tmp_r
        fi;
        reply = 0; tmp_r = 0; l = 0
       }
    od
}

/* === Shared PaymentService (single escrow ledger across both listings) === */
proctype PaymentService() {
    mtype:msg cmd;
    byte l, b, r;

end_payment:
    do
    :: atomic { pay_req ? cmd, l, b, r ->
        if
        :: (cmd == charge) ->
            if
            :: (l < M && b < N && r > NO_RES && r < MAX_RES_ID && charge_status[r] == CHG_NONE && balance[b] >= 1) ->
                d_step {
                    balance[b]--;
                    escrow++;
                    charge_status[r] = CHG_HELD;
                    charge_payer[r] = b;
                    charge_listing[r] = l;
                    assert(LEDGER_OK)
                };
                pay_resp ! charge_ok(l, b, r)
            :: pay_resp ! charge_fail(l, b, r)
            fi

        :: (cmd == payout) ->
            if
            :: (l < M && r > NO_RES && r < MAX_RES_ID && charge_status[r] == CHG_HELD && charge_listing[r] == l) ->
                d_step {
                    escrow--;
                    seller_bal[l]++;
                    charge_status[r] = CHG_PAID_OUT;
                    payout_res[l] = r;
                    assert(LEDGER_OK)
                };
                pay_resp ! payout_ok(l, b, r)
            :: else ->
                if
                :: (r > NO_RES && r < MAX_RES_ID && charge_status[r] == CHG_HELD && charge_listing[r] != l) ->
                    violation_cross_listing = true
                :: else ->
                    violation_dup_settlement = true
                fi
            fi

        :: (cmd == refund) ->
            if
            :: (l < M && b < N && r > NO_RES && r < MAX_RES_ID && charge_status[r] == CHG_HELD &&
                charge_payer[r] == b && charge_listing[r] == l) ->
                d_step {
                    escrow--;
                    balance[b]++;
                    charge_status[r] = CHG_REFUNDED;
                    assert(LEDGER_OK)
                };
                pay_resp ! refund_ok(l, b, r)
            :: else ->
                if
                :: (r > NO_RES && r < MAX_RES_ID && charge_status[r] == CHG_HELD && charge_listing[r] != l) ->
                    violation_cross_listing = true
                :: else ->
                    violation_dup_settlement = true
                fi
            fi

        :: else -> assert(false)
        fi;
        cmd = 0; l = 0; b = 0; r = 0
       }
    od
}

init {
    byte i = 0;
    atomic {
        run Marketplace();
        run PaymentService();
        run Seller(0);
        run Seller(1);
        do
        :: i < N ->
            run Buyer(i);
            i++
        :: else -> break
        od
    }
}

/* === LTL Specifications for M = 2 Listings === */
ltl S1 {
    [] ( (sale_count[0] <= 1) && (sale_count[1] <= 1) &&
         (ever_paid[0] -> (current_buyer[0] == sale_buyer[0] && current_res_id[0] == sale_res_id[0] &&
                           sale_buyer[0] != NO_BUYER && sale_res_id[0] != NO_RES)) &&
         (ever_paid[1] -> (current_buyer[1] == sale_buyer[1] && current_res_id[1] == sale_res_id[1] &&
                           sale_buyer[1] != NO_BUYER && sale_res_id[1] != NO_RES)) )
}

ltl S2 {
    [] ( !violation_mutex_reserve &&
         (ticket_state[0] == RESERVED -> (current_buyer[0] != NO_BUYER && current_res_id[0] != NO_RES)) &&
         (ticket_state[1] == RESERVED -> (current_buyer[1] != NO_BUYER && current_res_id[1] != NO_RES)) )
}

ltl S3 {
    [] ( !violation_bad_withdraw &&
         (ticket_state[0] == WITHDRAWN -> (!ever_paid[0] && !ever_delivered[0] && current_buyer[0] == NO_BUYER && [] (ticket_state[0] == WITHDRAWN))) &&
         (ticket_state[1] == WITHDRAWN -> (!ever_paid[1] && !ever_delivered[1] && current_buyer[1] == NO_BUYER && [] (ticket_state[1] == WITHDRAWN))) )
}

ltl S4 {
    [] ( !violation_stale_accept &&
         (payout_res[0] != NO_RES -> payout_res[0] == sale_res_id[0]) &&
         (payout_res[1] != NO_RES -> payout_res[1] == sale_res_id[1]) )
}

ltl S5 {
    [] ( (seller_bal[0] > 0 -> (ever_delivered[0] && deliveryConfirmed[0] && ticket_state[0] == SETTLED)) &&
         (seller_bal[1] > 0 -> (ever_delivered[1] && deliveryConfirmed[1] && ticket_state[1] == SETTLED)) )
}

ltl S6 {
    [] ( !violation_dup_settlement && !violation_cross_listing && seller_bal[0] <= 1 && seller_bal[1] <= 1 )
}

ltl S7 {
    [] LEDGER_OK
}

ltl L1 {
    [] ( (ticket_state[0] == RESERVED -> <> (ticket_state[0] == AVAILABLE || ticket_state[0] == PAID)) &&
         (ticket_state[1] == RESERVED -> <> (ticket_state[1] == AVAILABLE || ticket_state[1] == PAID)) )
}

ltl L2 {
    [] ( (ticket_state[0] == PAID -> <> (ever_delivered[0] || (ticket_state[0] == REFUNDED && charge_status[sale_res_id[0]] == CHG_REFUNDED))) &&
         (ticket_state[1] == PAID -> <> (ever_delivered[1] || (ticket_state[1] == REFUNDED && charge_status[sale_res_id[1]] == CHG_REFUNDED))) )
}

ltl L3 {
    [] ( escrow > 0 -> <> (escrow == 0) )
}

ltl L4 {
    [] ( stale_refund_pending > 0 -> <> (stale_refund_pending == 0) )
}

ltl L5 {
    [] ( (ticket_state[0] == PAID -> <> (ticket_state[0] == SETTLED || ticket_state[0] == REFUNDED)) &&
         (ticket_state[1] == PAID -> <> (ticket_state[1] == SETTLED || ticket_state[1] == REFUNDED)) )
}
