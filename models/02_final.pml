/*
 * 02_final.pml - Verified model of the Ticket Reservation System
 * Must satisfy all safety properties (S1-S9) and liveness properties (L1-L3).
 *
 * File Organization: Option A (Single-file section markers per team agreement)
 */

#include "defs.pml"

/* === M1 SECTION START: Marketplace === */
/* TODO (M1): Implement hardened Marketplace proctype with:
 *   - atomic/d_step serialisation
 *   - current_res_id & b == reserved_by / b == buyer_of_sale guards
 *   - reset cancelAccepted = false on AVAILABLE -> RESERVED
 *   - stale charge_ok -> pay_req ! refund(b, r) without mutating active sale
 *   - drain in-flight charges before entering terminal states (held_cnt == 0)
 *   - abstract RESERVED and PAID timeout branches
 */
proctype Marketplace() {
    mtype:msg msg;
    byte b, r;
    bool charge_in_flight = false;
    bool withdraw_pending = false;
    bool refund_in_flight = false;
    bool refund_done = false;
    bool payout_in_flight = false;
    bool payout_done = false;
    byte pending_charges = 0;
    byte pending_stale_refunds = 0;
    byte confirm_b = NO_BUYER;
    byte confirm_r = NO_RES;

    /* Phase 1: Active ticket lifecycle & stale-operation drain before terminal state */
    do
    :: is_terminal ->
        break

    /* Complete terminal transitions only after stale charges/refunds drain (guarantees S8 held_cnt == 0) */
    :: (withdraw_pending && pending_charges == 0 && pending_stale_refunds == 0) ->
        d_step {
            withdraw_pending = false;
            ticket_state = WITHDRAWN
        };
        seller_ch ! withdraw_ok

    :: (payout_done && pending_charges == 0 && pending_stale_refunds == 0) ->
        d_step {
            payout_done = false;
            ticket_state = SETTLED
        };
        if
        :: (confirm_b < N) -> buyer_ch[confirm_b] ! confirm_ok(confirm_r)
        :: else -> skip
        fi

    :: (refund_done && pending_charges == 0 && pending_stale_refunds == 0) ->
        d_step {
            refund_done = false;
            sale_refunded = true;
            ticket_state = REFUNDED
        }

    :: mkt_req ? msg, b, r ->
        if
        :: msg == reserve ->
            if
            :: (ticket_state == AVAILABLE && !withdraw_pending && b < N) ->
                d_step {
                    current_res_id = next_res_id;
                    if
                    :: (next_res_id == 255) -> next_res_id = 1
                    :: else -> next_res_id++
                    fi;
                    reserved_by = b;
                    cancelAccepted = false;
                    charge_in_flight = false;
                    ticket_state = RESERVED
                };
                buyer_ch[b] ! reserve_ok(current_res_id)
            :: else ->
                if
                :: (b < N) -> buyer_ch[b] ! reserve_fail(NO_RES)
                :: else -> skip
                fi
            fi

        :: msg == withdraw ->
            if
            :: (ticket_state == AVAILABLE && !withdraw_pending) ->
                d_step { withdraw_pending = true }
            :: else ->
                seller_ch ! withdraw_fail
            fi

        :: msg == pay ->
            if
            :: (ticket_state == RESERVED && b == reserved_by && r == current_res_id && r != NO_RES && !charge_in_flight && b < N) ->
                d_step {
                    charge_in_flight = true;
                    pending_charges++
                };
                pay_req ! charge(b, r)
            :: else ->
                if
                :: (b < N) -> buyer_ch[b] ! pay_fail(r)
                :: else -> skip
                fi
            fi

        :: msg == cancel ->
            if
            :: (ticket_state == RESERVED && b == reserved_by && r == current_res_id && r != NO_RES && b < N) ->
                d_step {
                    cancelAccepted = true;
                    reserved_by = NO_BUYER;
                    current_res_id = NO_RES;
                    charge_in_flight = false;
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
            :: (ticket_state == PAID && !refund_in_flight && !refund_done) ->
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
            :: (ticket_state == DELIVERED && !payout_in_flight && !payout_done && b == buyer_of_sale && r == current_res_id && r != NO_RES && b < N) ->
                d_step {
                    deliveryConfirmed = true;
                    confirmAccepted = true;
                    confirmed_by = b;
                    payout_in_flight = true
                };
                pay_req ! payout(b, r)
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
            :: (ticket_state == RESERVED && b == reserved_by && r == current_res_id && r != NO_RES) ->
                d_step {
                    if
                    :: (pending_charges > 0) -> pending_charges--
                    :: else -> skip
                    fi;
                    charge_in_flight = false;
                    buyer_of_sale = b;
                    ever_paid = true;
                    sale_count++;
                    ticket_state = PAID
                };
                if
                :: (b < N) -> buyer_ch[b] ! pay_ok(r)
                :: else -> skip
                fi
            :: else ->
                /* Stale charge_ok after timeout or cancellation: refund without mutating active sale */
                d_step {
                    if
                    :: (pending_charges > 0) -> pending_charges--
                    :: else -> skip
                    fi;
                    pending_stale_refunds++
                };
                pay_req ! refund(b, r);
                if
                :: (b < N) -> buyer_ch[b] ! pay_fail(r)
                :: else -> skip
                fi
            fi

        :: msg == charge_fail ->
            d_step {
                if
                :: (pending_charges > 0) -> pending_charges--
                :: else -> skip
                fi;
                if
                :: (ticket_state == RESERVED && b == reserved_by && r == current_res_id) ->
                    charge_in_flight = false
                :: else -> skip
                fi
            };
            if
            :: (b < N) -> buyer_ch[b] ! pay_fail(r)
            :: else -> skip
            fi

        :: msg == refund_ok ->
            if
            :: (refund_in_flight && ticket_state == PAID && b == buyer_of_sale && r == current_res_id) ->
                d_step {
                    refund_in_flight = false;
                    refund_done = true
                }
            :: else ->
                d_step {
                    if
                    :: (pending_stale_refunds > 0) -> pending_stale_refunds--
                    :: else -> skip
                    fi
                }
            fi

        :: msg == payout_ok ->
            if
            :: (payout_in_flight && ticket_state == DELIVERED && b == buyer_of_sale && r == current_res_id) ->
                d_step {
                    payout_in_flight = false;
                    payout_done = true;
                    confirm_b = b;
                    confirm_r = r
                }
            :: else -> skip
            fi

        :: else -> skip
        fi

    /* Abstract RESERVED timeout (buyer walked away or reservation expired) */
    :: d_step {
        (ticket_state == RESERVED) ->
        reserved_by = NO_BUYER;
        current_res_id = NO_RES;
        charge_in_flight = false;
        ticket_state = AVAILABLE
    }

    /* Abstract PAID timeout (seller failed to deliver in time) */
    :: d_step {
        (ticket_state == PAID && !refund_in_flight && !refund_done) ->
        refund_in_flight = true
    };
    pay_req ! refund(buyer_of_sale, current_res_id)
    od;

    /* Phase 2: Terminal drain loop (reject late requests cleanly without deadlocking participants) */
end_mkt:
    do
    :: mkt_req ? msg, b, r ->
        if
        :: (msg == reserve && b < N) -> buyer_ch[b] ! reserve_fail(NO_RES)
        :: (msg == pay && b < N)     -> buyer_ch[b] ! pay_fail(r)
        :: (msg == cancel && b < N)  -> buyer_ch[b] ! cancel_fail(r)
        :: (msg == confirm && b < N) -> buyer_ch[b] ! confirm_fail(r)
        :: (msg == withdraw)         -> seller_ch ! withdraw_fail
        :: (msg == deliver)          -> seller_ch ! deliver_fail
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
