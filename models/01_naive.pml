/*
 * 01_naive.pml - Naive (buggy) model of the Ticket Reservation System
 * Owner: M3. Purpose: reproduce concrete SPIN counterexamples for the
 * safety properties S1, S4, S5 and S7 (Barrier 2), and illustrate the
 * liveness failures L3/L4 that a missing stale-charge refund causes.
 *
 * Everything that is NOT a bug is identical to 02_final.pml: the same
 * defs.pml, the same Seller/Buyer (M2 section is copied verbatim), the same
 * ghost observers, the same atomic message handling (Assumption 3) and the
 * same properties.pml. Each counterexample therefore points at exactly one
 * injected defect. Every defect is tagged [BUG-n] in the code.
 *
 *  [BUG-1] -> S1  Re-entrant payment acceptance. charge_ok is accepted while
 *                 RESERVED *or already PAID* ("a duplicate confirmation is
 *                 harmless"), so a second charge_ok sells the listing again
 *                 and overwrites current_res_id.
 *  [BUG-2] -> S4  ABA stale-charge acceptance. charge_ok is matched on the
 *                 buyer id only, not on the reservation id, so a late
 *                 charge_ok(b, r1) from b's expired attempt is accepted for
 *                 b's new reservation r2 (the exact scenario of the proposal's
 *                 "Why res_id is required" rationale).
 *  [BUG-3] -> S5  Unguarded confirmation. confirm is accepted in PAID as well
 *                 as DELIVERED and without checking (b, r), so any buyer can
 *                 trigger the seller payout before the ticket is delivered.
 *  [BUG-4] -> S7  Optimistic refund-on-cancel + unchecked refund.
 *                 (a) cancel immediately sends refund(b, r), assuming the
 *                     charge already succeeded, although charge(b, r) may
 *                     still be pending or be declined;
 *                 (b) the naive PaymentService refunds/pays out without
 *                     checking that the charge is HELD, and clamps escrow at
 *                     0 instead of rejecting, so money is created.
 *  [BUG-5] -> L3, L4  Stale charge_ok is silently dropped (no refund), so the
 *                 buyer's money stays in escrow forever.
 *
 * Note on "missing atomicity": the Marketplace is the single consumer of
 * mkt_req/pay_resp, so a non-atomic handler cannot be interleaved with
 * another handler of the same process. Splitting handlers would only expose
 * torn intermediate states to the never claim (a modelling artefact, not a
 * protocol bug), so the injected defects are guard/logic defects instead.
 */

#include "defs.pml"

/* === M1 SECTION START: Naive Marketplace (Buggy) === */
proctype Marketplace() {
    mtype:msg msg;
    byte b, r, assigned_r;

end_active:
    do
    :: is_terminal ->
        break

    /* ---- user commands ---- */
    :: atomic { (nfull(pay_req) && nempty(mkt_req)) ->
        mkt_req ? msg, b, r;
        if
        :: msg == reserve ->
            if
            :: (ticket_state == AVAILABLE && b < N && next_res_id < MAX_RES_ID) ->
                d_step {
                    OBS_RESERVE_GRANT();
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
                    OBS_WITHDRAW();
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
                pay_req ! refund(b, r);              /* [BUG-4a] refund before the charge outcome is known */
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
            :: (ticket_state == PAID || ticket_state == DELIVERED) && b < N ->   /* [BUG-3] no DELIVERED-only, no (b, r) check */
                d_step {
                    deliveryConfirmed = true;
                    ticket_state = SETTLED
                };
                pay_req ! payout(current_buyer, current_res_id);
                buyer_ch[b] ! confirm_ok(r)
            :: else ->
                if
                :: (b < N) -> buyer_ch[b] ! confirm_fail(r)
                :: else -> skip
                fi
            fi

        :: else -> skip
        fi;
        msg = 0; b = 0; r = 0; assigned_r = 0
       }

    /* ---- payment results ---- */
    :: atomic { pay_resp ? msg, b, r ->
        if
        :: msg == charge_ok ->
            if
            :: (ticket_state == RESERVED || ticket_state == PAID) && b == current_buyer ->  /* [BUG-1] re-entry, [BUG-2] no r check */
                d_step {
                    OBS_CHARGE_ACCEPT(b, r);
                    if
                    :: !ever_paid -> sale_buyer = b; sale_res_id = r   /* ghost: latch the FIRST sale */
                    :: else -> skip
                    fi;
                    ever_paid = true;
                    sale_count++;
                    current_res_id = r;               /* "bind the paid reservation" */
                    ticket_state = PAID
                }
            :: else ->
                d_step { stale_refund_pending++ }    /* ghost: a refund is now owed       */
                                                      /* [BUG-5] ...but none is ever sent */
            fi

        :: msg == charge_fail ->
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
        msg = 0; b = 0; r = 0
       }

    /* FR-8(c): Abstract res_timeout (RESERVED -> AVAILABLE) */
    :: d_step {
        (ticket_state == RESERVED) ->
        current_buyer = NO_BUYER;
        current_res_id = NO_RES;
        ticket_state = AVAILABLE
    }

    /* FR-10(b): Abstract delivery_timeout (PAID -> REFUNDED) */
    :: atomic { (ticket_state == PAID && nfull(pay_req)) ->
        d_step {
            delivery_timed_out = true;
            ticket_state = REFUNDED
        };
        pay_req ! refund(current_buyer, current_res_id)
       }

    /* FR-11(b): Abstract confirm_timeout (DELIVERED -> SETTLED) */
    :: atomic { (ticket_state == DELIVERED && nfull(pay_req)) ->
        d_step {
            deliveryConfirmed = true;
            ticket_state = SETTLED
        };
        pay_req ! payout(current_buyer, current_res_id)
       }
    od;

end_mkt:
    do
    :: atomic { mkt_req ? msg, b, r ->
        if
        :: (msg == reserve && b < N) -> buyer_ch[b] ! reserve_fail(NO_RES)
        :: (msg == cancel && b < N)  -> buyer_ch[b] ! cancel_fail(r)
        :: (msg == confirm && b < N) -> buyer_ch[b] ! confirm_fail(r)
        :: (msg == withdraw)         -> seller_ch ! withdraw_fail
        :: (msg == deliver)          -> seller_ch ! deliver_fail
        :: else -> skip
        fi;
        msg = 0; b = 0; r = 0
       }

    :: atomic { pay_resp ? msg, b, r ->
        if
        :: msg == charge_ok ->
            d_step { stale_refund_pending++ }        /* [BUG-5] owed, never refunded */
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
        msg = 0; b = 0; r = 0
       }
    od;
}
/* === M1 SECTION END: Naive Marketplace === */

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


/* === M3 SECTION START: Naive PaymentService (Buggy) === */
/*
 * Same atomic ledger operations as 02_final.pml, but payout/refund trust the
 * caller: they do not check that the charge is HELD (or who paid it), and
 * they clamp escrow at 0 instead of rejecting. The S6 observer line is the
 * same instrumentation as in the final model; it only records the fact.
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
                    charge_payer[r] = b
                };
                pay_resp ! charge_ok(b, r)
            :: pay_resp ! charge_fail(b, r)
            fi

        :: cmd == payout ->                          /* [BUG-4b] no HELD check, escrow clamped */
            d_step {
                violation_dup_settlement = (violation_dup_settlement || charge_status[r] != CHG_HELD);
                seller_bal++;
                if
                :: escrow > 0 -> escrow--
                :: else -> skip
                fi;
                charge_status[r] = CHG_PAID_OUT;
                payout_res = r
            };
            pay_resp ! payout_ok(b, r)

        :: cmd == refund ->                          /* [BUG-4b] no HELD check, escrow clamped */
            d_step {
                violation_dup_settlement = (violation_dup_settlement || charge_status[r] != CHG_HELD);
                balance[b]++;
                if
                :: escrow > 0 -> escrow--
                :: else -> skip
                fi;
                charge_status[r] = CHG_REFUNDED
            };
            pay_resp ! refund_ok(b, r)

        :: else -> skip
        fi;
        cmd = 0; b = 0; r = 0
       }
    od
}
/* === M3 SECTION END: Naive PaymentService === */

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
