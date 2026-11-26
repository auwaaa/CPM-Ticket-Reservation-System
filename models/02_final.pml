/*
 * 02_final.pml - Verified model of the Ticket Reservation System
 * Must satisfy all safety properties (S1-S9) and liveness properties (L1-L3).
 */

#include "defs.pml"

/* === M1 SECTION === */
proctype Marketplace() {
    mtype:msg msg;
    byte b, r;
    bool charge_in_flight = false;
    bool refund_in_flight = false;
    bool payout_in_flight = false;
    byte pending_charges = 0;
    byte pending_stale_refunds = 0;

    /* Phase 1: Active ticket lifecycle & in-flight payment settlement */
    do
    :: ((ticket_state == SETTLED || ticket_state == WITHDRAWN || ticket_state == REFUNDED)
        && pending_charges == 0
        && pending_stale_refunds == 0
        && !refund_in_flight
        && !payout_in_flight) ->
        break

    :: mkt_req ? msg, b, r ->
        if
        :: msg == reserve ->
            if
            :: (ticket_state == AVAILABLE && b < N) ->
                d_step {
                    current_res_id = next_res_id;
                    if
                    :: (next_res_id >= MAX_RES) -> next_res_id = 1
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
            :: (ticket_state == AVAILABLE) ->
                d_step { ticket_state = WITHDRAWN };
                seller_ch ! withdraw_ok
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
            :: (ticket_state == PAID && !refund_in_flight) ->
                d_step { ticket_state = DELIVERED };
                seller_ch ! deliver_ok
            :: else ->
                seller_ch ! deliver_fail
            fi

        :: msg == confirm ->
            if
            :: (ticket_state == DELIVERED && !payout_in_flight && b == buyer_of_sale && r == current_res_id && r != NO_RES && b < N) ->
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
                    pending_charges--;
                    charge_in_flight = false;
                    buyer_of_sale = b;
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
                    ticket_state = REFUNDED
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
                    ticket_state = SETTLED
                };
                if
                :: (b < N) -> buyer_ch[b] ! confirm_ok(r)
                :: else -> skip
                fi
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
        (ticket_state == PAID && !refund_in_flight) ->
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
/* === END M1 SECTION === */

/* === M2 SECTION === */
/* TODO (M2): Implement Seller proctype */
proctype Seller() {
    skip;
}

/* TODO (M2): Implement Buyer proctype (parameterized by byte id) */
proctype Buyer(byte id) {
    skip;
}
/* === END M2 SECTION === */

/* === M3 SECTION === */
/* TODO (M3): Implement PaymentService proctype */
proctype PaymentService() {
    skip;
}
/* === END M3 SECTION === */

/* === M1 SECTION (init) === */
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
/* === END M1 SECTION (init) === */

/* === M3 SECTION (LTL) === */
/* TODO (M3): Add LTL properties S1-S9 (safety) and L1-L3 (liveness) */
/* === END M3 SECTION (LTL) === */
