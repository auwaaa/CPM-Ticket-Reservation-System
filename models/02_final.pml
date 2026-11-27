/*
 * 02_final.pml - Hardened model of the Ticket Reservation System
 * Must satisfy all safety properties (S1-S7), deadlock freedom, and
 * liveness properties (L1-L5) of docs/revised_project_proposal.md.
 *
 * File Organization: Option A (single-file section markers per team agreement)
 *
 * Lines tagged [M3] inside M1's section were added by M3 and do not change
 * the protocol logic:
 *   - OBS_* calls: ghost observers (they only write violation_* ghosts);
 *   - atomic { ... } around each message handler: Assumption 3 / FR-2
 *     ("the marketplace handles one message to completion before the next")
 *     made explicit, which removes meaningless interleavings;
 *   - msg = 0; b = 0; r = 0 at the end of a handler: clears dead locals so
 *     that states differing only in "last message seen" are merged.
 * The M2 section is a contract-compliant REFERENCE Seller/Buyer written by M3
 * so the model can be verified end-to-end; M2 owns it and may replace it.
 */

#include "defs.pml"

/* === M1 SECTION START: Marketplace === */
proctype Marketplace() {
    mtype:msg msg;
    byte b, r, assigned_r;

    /* Phase 1: Active ticket lifecycle (FR-1..FR-11, Assumption 6).
     * end_active [M3]: an unsold listing with no pending work (buyers out of
     * attempts, seller idle) is a legitimate quiescent state, not a deadlock. */
end_active:
    do
    :: is_terminal ->
        break

    /* ---- user commands ---- */
    :: atomic { (nfull(pay_req) && nempty(mkt_req)) ->            /* [M3] atomic */
        mkt_req ? msg, b, r;
        if
        :: msg == reserve ->
            if
            :: (ticket_state == AVAILABLE && b < N && next_res_id < MAX_RES_ID) ->
                d_step {
                    OBS_RESERVE_GRANT();                            /* [M3] S2 observer */
                    assigned_r = next_res_id;
                    current_res_id = assigned_r;
                    next_res_id++;
                    current_buyer = b;
                    ticket_state = RESERVED
                };
                buyer_ch[b] ! reserve_ok(assigned_r);
                pay_req ! charge(b, assigned_r)
            :: else ->
                if
                :: (b < N) -> buyer_ch[b] ! reserve_fail(NO_RES)
                :: else -> skip
                fi
            fi

        :: msg == withdraw ->
            if
            :: (ticket_state == AVAILABLE) ->
                d_step {
                    OBS_WITHDRAW();                                 /* [M3] S3 observer */
                    ticket_state = WITHDRAWN
                };
                seller_ch ! withdraw_ok
            :: else ->
                seller_ch ! withdraw_fail
            fi

        :: msg == cancel ->
            if
            :: (ticket_state == RESERVED && b == current_buyer && r == current_res_id && r != NO_RES && b < N) ->
                d_step {
                    current_buyer = NO_BUYER;
                    current_res_id = NO_RES;
                    ticket_state = AVAILABLE
                };
                buyer_ch[b] ! cancel_ok(r)
            :: else ->
                if
                :: (b < N) -> buyer_ch[b] ! cancel_fail(r)
                :: else -> skip
                fi
            fi

        :: msg == deliver ->
            if
            :: (ticket_state == PAID) ->
                d_step {
                    ever_delivered = true;
                    ticket_state = DELIVERED
                };
                seller_ch ! deliver_ok
            :: else ->
                seller_ch ! deliver_fail
            fi

        :: msg == confirm ->
            if
            :: (ticket_state == DELIVERED && b == current_buyer && r == current_res_id && r != NO_RES && b < N) ->
                d_step {
                    deliveryConfirmed = true;
                    ticket_state = SETTLED
                };
                pay_req ! payout(b, r);
                buyer_ch[b] ! confirm_ok(r)
            :: else ->
                if
                :: (b < N) -> buyer_ch[b] ! confirm_fail(r)
                :: else -> skip
                fi
            fi

        :: else -> skip
        fi;
        msg = 0; b = 0; r = 0; assigned_r = 0                       /* [M3] clear dead locals */
       }

    /* ---- payment results ---- */
    :: atomic { pay_resp ? msg, b, r ->                              /* [M3] atomic */
        if
        :: msg == charge_ok ->
            if
            :: (ticket_state == RESERVED && b == current_buyer && r == current_res_id && r != NO_RES) ->
                d_step {
                    OBS_CHARGE_ACCEPT(b, r);                        /* [M3] S4 observer */
                    ever_paid = true;
                    sale_count++;
                    sale_buyer = b;
                    sale_res_id = r;
                    ticket_state = PAID
                }
            :: else ->
                /* FR-9 / S4 / L4: Stale charge_ok triggers refund without mutating listing state */
                d_step { stale_refund_pending++ };
                pay_req ! refund(b, r)
            fi

        :: msg == charge_fail ->
            /* FR-8(a): Matching charge_fail releases active reservation back to AVAILABLE */
            if
            :: (ticket_state == RESERVED && b == current_buyer && r == current_res_id && r != NO_RES) ->
                d_step {
                    current_buyer = NO_BUYER;
                    current_res_id = NO_RES;
                    ticket_state = AVAILABLE
                }
            :: else -> skip
            fi

        :: msg == refund_ok ->
            if
            :: (r != sale_res_id) ->
                d_step {
                    if
                    :: (stale_refund_pending > 0) -> stale_refund_pending--
                    :: else -> skip
                    fi
                }
            :: else -> skip
            fi

        :: msg == payout_ok ->
            skip

        :: else -> skip
        fi;
        msg = 0; b = 0; r = 0                                       /* [M3] clear dead locals */
       }

    /* FR-8(c): Abstract res_timeout (RESERVED -> AVAILABLE) */
    :: d_step {
        (ticket_state == RESERVED) ->
        current_buyer = NO_BUYER;
        current_res_id = NO_RES;
        ticket_state = AVAILABLE
    }

    /* FR-10(b): Abstract delivery_timeout (PAID -> REFUNDED) */
    :: atomic { (ticket_state == PAID && nfull(pay_req)) ->          /* [M3] atomic */
        d_step {
            delivery_timed_out = true;
            ticket_state = REFUNDED
        };
        pay_req ! refund(current_buyer, current_res_id)
       }

    /* FR-11(b), Assumption 6: Abstract confirm_timeout (DELIVERED -> SETTLED) */
    :: atomic { (ticket_state == DELIVERED && nfull(pay_req)) ->     /* [M3] atomic */
        d_step {
            deliveryConfirmed = true;
            ticket_state = SETTLED
        };
        pay_req ! payout(current_buyer, current_res_id)
       }
    od;

    /* Phase 2: Terminal drain loop (reject late user commands & refund late stale charges per L3/L4) */
end_mkt:
    do
    :: atomic { mkt_req ? msg, b, r ->                               /* [M3] atomic */
        if
        :: (msg == reserve && b < N) -> buyer_ch[b] ! reserve_fail(NO_RES)
        :: (msg == cancel && b < N)  -> buyer_ch[b] ! cancel_fail(r)
        :: (msg == confirm && b < N) -> buyer_ch[b] ! confirm_fail(r)
        :: (msg == withdraw)         -> seller_ch ! withdraw_fail
        :: (msg == deliver)          -> seller_ch ! deliver_fail
        :: else -> skip
        fi;
        msg = 0; b = 0; r = 0                                       /* [M3] clear dead locals */
       }

    :: atomic { pay_resp ? msg, b, r ->                              /* [M3] atomic */
        if
        :: msg == charge_ok ->
            d_step { stale_refund_pending++ };
            pay_req ! refund(b, r)
        :: msg == refund_ok ->
            if
            :: (r != sale_res_id) ->
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
        msg = 0; b = 0; r = 0                                       /* [M3] clear dead locals */
       }
    od;
}
/* === M1 SECTION END: Marketplace === */

/* === M2 SECTION START: Participants (Seller & Buyer) === */
/*
 * REFERENCE IMPLEMENTATION by M3, written to the M2 contract in
 * docs/temp_role_execution_plan.md §4.1 so S1-S7 / L1-L5 can be verified
 * end-to-end. M2 (Uy) owns this section and may refine or replace it.
 * 01_naive.pml uses the identical Seller/Buyer, so the naive and the hardened
 * model differ ONLY in Marketplace and PaymentService.
 *
 * Design rules:
 *  - every command is immediately followed by reading its 1-to-1 reply (FR-3);
 *  - each "decide -> send -> await reply" step is one atomic action of the
 *    participant (it blocks inside the atomic until the reply arrives, which
 *    lets the other processes run in the meantime);
 *  - every non-deterministic choice is made once (bounded by flags), so there
 *    are no busy-wait `skip` loops that could hide liveness violations;
 *  - an idle participant blocks at an end-label, which is a valid end state.
 *    There is deliberately no `:: is_terminal -> break`: every guard is false
 *    once the listing is terminal, so participants stop cleanly anyway, and
 *    the N+1 possible orders of "who exits first" are not explored (this
 *    alone cut the N=2, K=2 state space from 20.0 M to 12.4 M states);
 *  - a buyer only tries to reserve when it sees the listing AVAILABLE, and
 *    only spoofs while ANOTHER buyer holds the listing (the only moment a
 *    spoof can do harm). Both keep the FR-4 race and the ABA scenario while
 *    pruning interleavings that can only be rejected.
 */
#define SELLER_ID 0   /* sender_id field is unused for seller commands */

proctype Seller() {
    mtype:msg reply;
    bool withdraw_tried  = false;
    bool deliver_decided = false;

end_seller:
    do
    /* FR-5: optionally withdraw while AVAILABLE (may race with a reserve) */
    :: atomic { (ticket_state == AVAILABLE && !withdraw_tried) ->
        withdraw_tried = true;
        mkt_req ! withdraw(SELLER_ID, NO_RES);
        seller_ch ? reply;
        reply = 0
       }

    /* FR-10: in PAID, either deliver (races with delivery_timeout) or never deliver */
    :: atomic { (ticket_state == PAID && !deliver_decided) ->
        deliver_decided = true;
        if
        :: mkt_req ! deliver(SELLER_ID, NO_RES);
           seller_ch ? reply;
           reply = 0
        :: skip    /* non-delivery: delivery_timeout must refund the buyer (L2) */
        fi
       }
    od
}

proctype Buyer(byte id) {
    mtype:msg reply;
    byte attempts = 0;          /* FR-12: at most K reservation attempts */
    byte my_res   = NO_RES;     /* latest reservation id granted to this buyer */
    byte tmp_r    = NO_RES;
    bool confirm_decided = false;
    bool spoofed  = false;

end_buyer:
    do
    /* FR-4 / FR-6: reserve; the Marketplace auto-charges on accept (no `pay` command) */
    :: atomic { (attempts < K && ticket_state == AVAILABLE) ->
        attempts++;
        mkt_req ! reserve(id, NO_RES);
        buyer_ch[id] ? reply, tmp_r;
        if
        :: reply == reserve_ok ->
            my_res = tmp_r;
            if
            :: mkt_req ! cancel(id, my_res);    /* FR-8(b): races with charge result / res_timeout */
               buyer_ch[id] ? reply, tmp_r
            :: skip                            /* wait or abandon: charge / res_timeout resolve it */
            fi
        :: else -> skip                        /* reserve_fail: lost the race */
        fi;
        reply = 0; tmp_r = 0
       }

    /* FR-11: the winning buyer either confirms explicitly or stays silent (confirm_timeout) */
    :: atomic { (ticket_state == DELIVERED && current_buyer == id && !confirm_decided) ->
        confirm_decided = true;
        if
        :: mkt_req ! confirm(id, my_res);
           buyer_ch[id] ? reply, tmp_r
        :: skip
        fi;
        reply = 0; tmp_r = 0
       }

    /* Spoofed / stale request, at most once per buyer: must be rejected without effect */
    :: atomic { (!spoofed && current_buyer != id && current_buyer != NO_BUYER && !is_terminal) ->
        spoofed = true;
        if
        :: mkt_req ! cancel(id, 1);  buyer_ch[id] ? reply, tmp_r
        :: mkt_req ! confirm(id, 1); buyer_ch[id] ? reply, tmp_r
        fi;
        reply = 0; tmp_r = 0
       }
    od
}
/* === M2 SECTION END: Participants (Seller & Buyer) === */

/* === M3 SECTION START: PaymentService === */
/*
 * Atomic integer escrow ledger (Assumption 7) with per-charge single
 * settlement (S6). Every ledger mutation is one d_step, so no process and no
 * never claim can observe a half-done transfer (S7 holds in EVERY state).
 *
 *   charge(b, r) : balance[b] -1, escrow +1, charge_status[r]: NONE -> HELD
 *                  (or a non-deterministic decline -> charge_fail)
 *   payout(b, r) : escrow -1, seller_bal +1,     charge_status[r]: HELD -> PAID_OUT
 *   refund(b, r) : escrow -1, balance[b] +1,     charge_status[r]: HELD -> REFUNDED
 *
 * A payout/refund whose charge is not HELD (never charged, declined, or
 * already settled) moves NO money: it is rejected and recorded in the
 * violation_dup_settlement ghost, so S6 reports the protocol error.
 * A refund must name the buyer who was actually charged for r (checked
 * against charge_payer[r]), so money can never be refunded to someone else.
 */
proctype PaymentService() {
    mtype:msg cmd;
    byte b, r;

end_payment:
    do
    :: atomic { pay_req ? cmd, b, r ->
        if
        :: cmd == charge ->
            if
            :: (b < N && r > NO_RES && r < MAX_RES_ID && charge_status[r] == CHG_NONE && balance[b] >= 1) ->
                d_step {
                    balance[b]--;
                    escrow++;
                    charge_status[r] = CHG_HELD;
                    charge_payer[r] = b;
                    assert(LEDGER_OK)
                };
                pay_resp ! charge_ok(b, r)
            :: pay_resp ! charge_fail(b, r)        /* gateway declines (Assumption 4: always answers) */
            fi

        :: cmd == payout ->
            if
            :: (r > NO_RES && r < MAX_RES_ID && charge_status[r] == CHG_HELD) ->
                d_step {
                    escrow--;
                    seller_bal++;
                    charge_status[r] = CHG_PAID_OUT;
                    payout_res = r;
                    assert(LEDGER_OK)
                };
                pay_resp ! payout_ok(b, r)
            :: else ->
                violation_dup_settlement = true     /* rejected: unbacked or duplicate payout */
            fi

        :: cmd == refund ->
            if
            :: (b < N && r > NO_RES && r < MAX_RES_ID && charge_status[r] == CHG_HELD && charge_payer[r] == b) ->
                d_step {
                    escrow--;
                    balance[b]++;
                    charge_status[r] = CHG_REFUNDED;
                    assert(LEDGER_OK)
                };
                pay_resp ! refund_ok(b, r)
            :: else ->
                violation_dup_settlement = true     /* rejected: unbacked, duplicate or misdirected refund */
            fi

        :: else ->
            assert(false)                           /* only charge/payout/refund travel on pay_req */
        fi;
        cmd = 0; b = 0; r = 0                       /* clear dead locals */
       }
    od
}
/* === M3 SECTION END: PaymentService === */

/* === M1 SECTION START: Init === */
init {
    byte i = 0;
    atomic {
        run Marketplace();
        run PaymentService();
        run Seller();
        do
        :: i < N ->
            run Buyer(i);
            i++
        :: else -> break
        od;
    }
}
/* === M1 SECTION END: Init === */

/* === M3 SECTION START: LTL Specifications (S1-S7, L1-L5) === */
#include "properties.pml"
/* === M3 SECTION END: LTL Specifications (S1-S7, L1-L5) === */
