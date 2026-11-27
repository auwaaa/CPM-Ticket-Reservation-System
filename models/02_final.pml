/*
 * 02_final.pml - Verified model of the Ticket Reservation System
 * Must satisfy all safety properties (S1-S9) and liveness properties (L1-L3).
 *
 * File Organization: Option A (Single-file section markers per team agreement)
 */

#include "defs.pml"

/* === M1 SECTION START: Marketplace === */
proctype Marketplace() {
    mtype:msg msg;
    byte b, r, assigned_r;

    /* Phase 1: Active ticket lifecycle (FR-1..FR-11, Assumption 6) */
    do
    :: is_terminal ->
        break

    :: (nfull(pay_req) && nempty(mkt_req)) ->
        mkt_req ? msg, b, r;
        if
        :: msg == reserve ->
            if
            :: (ticket_state == AVAILABLE && b < N && next_res_id < MAX_RES_ID) ->
                d_step {
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
                d_step { ticket_state = WITHDRAWN };
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
        fi

    :: pay_resp ? msg, b, r ->
        if
        :: msg == charge_ok ->
            if
            :: (ticket_state == RESERVED && b == current_buyer && r == current_res_id && r != NO_RES) ->
                d_step {
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
        fi

    /* FR-8(c): Abstract res_timeout (RESERVED -> AVAILABLE) */
    :: d_step {
        (ticket_state == RESERVED) ->
        current_buyer = NO_BUYER;
        current_res_id = NO_RES;
        ticket_state = AVAILABLE
    }

    /* FR-10(b): Abstract delivery_timeout (PAID -> REFUNDED) */
    :: (ticket_state == PAID && nfull(pay_req)) ->
        d_step {
            delivery_timed_out = true;
            ticket_state = REFUNDED
        };
        pay_req ! refund(current_buyer, current_res_id)

    /* FR-11(b), Assumption 6: Abstract confirm_timeout (DELIVERED -> SETTLED) */
    :: (ticket_state == DELIVERED && nfull(pay_req)) ->
        d_step {
            deliveryConfirmed = true;
            ticket_state = SETTLED
        };
        pay_req ! payout(current_buyer, current_res_id)
    od;

    /* Phase 2: Terminal drain loop (reject late user commands & refund late stale charges per L3/L4) */
end_mkt:
    do
    :: mkt_req ? msg, b, r ->
        if
        :: (msg == reserve && b < N) -> buyer_ch[b] ! reserve_fail(NO_RES)
        :: (msg == cancel && b < N)  -> buyer_ch[b] ! cancel_fail(r)
        :: (msg == confirm && b < N) -> buyer_ch[b] ! confirm_fail(r)
        :: (msg == withdraw)         -> seller_ch ! withdraw_fail
        :: (msg == deliver)          -> seller_ch ! deliver_fail
        :: else -> skip
        fi

    :: pay_resp ? msg, b, r ->
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
        fi
    od;
}
/* === M1 SECTION END: Marketplace === */

/* === M2 SECTION START: Participants (Seller & Buyer) === */
/* TODO (M2): Implement Seller proctype */
proctype Seller() {
    skip;
}

/* TODO (M2): Implement Buyer proctype (parameterized by byte id, K = 2 retries, Assumption A9) */
proctype Buyer(byte id) {
    skip;
}
/* === M2 SECTION END: Participants (Seller & Buyer) === */

/* === M3 SECTION START: PaymentService === */
/* TODO (M3): Implement PaymentService proctype */
proctype PaymentService() {
    mtype:msg cmd;
    byte b;
    byte r;

end_payment:
    do
    :: pay_req ? cmd, b, r ->
        if
        :: cmd == charge ->
            /* Non-deterministic payment gateway outcome: charge succeeds or fails */
            if
            :: atomic {
                   charged_cnt++;
                   held_cnt++;
                   assert(charged_cnt == held_cnt + paidOut_cnt + refunded_cnt);
               }
               pay_resp ! charge_ok(b, r)
            :: pay_resp ! charge_fail(b, r)
            fi
        :: cmd == payout ->
            atomic {
                assert(held_cnt > 0);
                held_cnt--;
                paidOut_cnt++;
                assert(charged_cnt == held_cnt + paidOut_cnt + refunded_cnt);
            }
            pay_resp ! payout_ok(b, r)
        :: cmd == refund ->
            atomic {
                assert(held_cnt > 0);
                held_cnt--;
                refunded_cnt++;
                assert(charged_cnt == held_cnt + paidOut_cnt + refunded_cnt);
            }
            pay_resp ! refund_ok(b, r)
        :: else ->
            assert(false)
        fi
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

/* === M3 SECTION START: LTL Specifications (S1-S9, L1-L3) === */
/* TODO (M3): Add LTL properties S1-S9 (safety) and L1-L3 (liveness) */

/* === M3 SECTION START: LTL Specifications (S1-S9, L1-L3) === */
/* Note: No X (next-state) operator is used so SPIN Partial-Order Reduction stays active. */

/* S1: No double-sale / single winning buyer */
ltl S1 {
    [] (
        (sale_count <= 1) &&
        (ticket_state == SETTLED -> (buyer_of_sale != NO_BUYER && confirmed_by == buyer_of_sale))
    )
}

/* S2: Payment precedes delivery and settlement */
ltl S2 {
    [] (
        (ticket_state == DELIVERED -> ever_paid) &&
        (ticket_state == SETTLED -> (ever_paid && ever_delivered && deliveryConfirmed))
    )
}

/* S3: Terminal state immutability (no transition out of SETTLED, WITHDRAWN, or REFUNDED) */
ltl S3 {
    [] (
        (ticket_state == SETTLED   -> [] (ticket_state == SETTLED)) &&
        (ticket_state == WITHDRAWN -> [] (ticket_state == WITHDRAWN)) &&
        (ticket_state == REFUNDED  -> [] (ticket_state == REFUNDED))
    )
}

/* S4: Withdrawal safety (cannot withdraw after reservation ownership or payment) */
ltl S4 {
    [] (
        ticket_state == WITHDRAWN ->
            (!ever_paid && !ever_delivered && reserved_by == NO_BUYER && buyer_of_sale == NO_BUYER)
    )
}

/* S5: Cancel vs. Confirm mutual exclusion and no cancel after payment */
ltl S5 {
    [] (
        !(cancelAccepted && confirmAccepted) &&
        (ever_paid -> !cancelAccepted)
    )
}

/* S6: Payout vs. active-sale refund mutual exclusion (allows prior stale-charge refunds) */
ltl S6 {
    [] (
        (paidOut_cnt <= 1) &&
        (ticket_state == SETTLED  -> (paidOut_cnt == 1 && !sale_refunded)) &&
        (ticket_state == REFUNDED -> (paidOut_cnt == 0 && sale_refunded))
    )
}

/* S7: Escrow hold invariant (no payout/refund without prior charge; active sale backed by charge) */
ltl S7 {
    [] (
        (paidOut_cnt + refunded_cnt <= charged_cnt) &&
        (held_cnt <= charged_cnt) &&
        ((ticket_state == PAID || ticket_state == DELIVERED) -> charged_cnt >= 1)
    )
}

/* S8: Money conservation & no unrefunded stale charge at terminal state */
ltl S8 {
    [] (
        (charged_cnt == held_cnt + paidOut_cnt + refunded_cnt) &&
        (is_terminal -> held_cnt == 0)
    )
}

/* S9: Buyer authorization (only buyer_of_sale can confirm; paid/delivered/settled have valid owner) */
ltl S9 {
    [] (
        (confirmAccepted -> (confirmed_by == buyer_of_sale && buyer_of_sale != NO_BUYER)) &&
        ((ticket_state == PAID || ticket_state == DELIVERED || ticket_state == SETTLED) -> buyer_of_sale != NO_BUYER)
    )
}

/* L1: Paid ticket eventually reaches SETTLED or REFUNDED (under weak fairness, A6/A9) */
ltl L1 {
    [] (ticket_state == PAID -> <> (ticket_state == SETTLED || ticket_state == REFUNDED))
}

/* L2: Delivered ticket eventually reaches SETTLED (under Assumption A9) */
ltl L2 {
    [] (ticket_state == DELIVERED -> <> (ticket_state == SETTLED))
}

/* L3: System eventually reaches a terminal state (SETTLED, WITHDRAWN, or REFUNDED) */
ltl L3 {
    <> (ticket_state == SETTLED || ticket_state == WITHDRAWN || ticket_state == REFUNDED)
}
/* === M3 SECTION END: LTL Specifications (S1-S9, L1-L3) === */
