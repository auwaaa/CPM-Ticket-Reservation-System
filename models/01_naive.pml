/*
 * 01_naive.pml - Initial naive model of the Ticket Reservation System
 * Expected to expose concurrency flaws / LTL violations for trail capture.
 */

#include "defs.pml"

/* === M1 SECTION === */
/*
 * Base unhardened Marketplace() skeleton (M1).
 * Intentionally omits d_step/atomic serialisation, res_id checks,
 * buyer_id (b == reserved_by / b == buyer_of_sale) authorisation checks,
 * cancel state restriction, and stale-charge refund logic.
 * NOTE: M3 owns final bug-injection tuning for S1, S5, S8, S9.
 */
proctype Marketplace() {
    mtype:msg msg;
    byte b, r;

    do
    :: (ticket_state == SETTLED || ticket_state == WITHDRAWN || ticket_state == REFUNDED) ->
        break

    :: mkt_req ? msg, b, r ->
        if
        :: msg == reserve ->
            if
            :: (ticket_state == AVAILABLE && b < N) ->
                reserved_by = b;
                current_res_id = next_res_id;
                if
                :: (next_res_id >= MAX_RES) -> next_res_id = 1
                :: else -> next_res_id++
                fi;
                ticket_state = RESERVED;
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
                ticket_state = WITHDRAWN;
                seller_ch ! withdraw_ok
            :: else ->
                seller_ch ! withdraw_fail
            fi

        :: msg == pay ->
            /* Buggy: omits b == reserved_by and r == current_res_id checks */
            if
            :: (ticket_state == RESERVED && b < N) ->
                pay_req ! charge(b, r)
            :: else ->
                if
                :: (b < N) -> buyer_ch[b] ! pay_fail(r)
                :: else -> skip
                fi
            fi

        :: msg == cancel ->
            /* Buggy: allows cancel across RESERVED/PAID/DELIVERED without ownership/res_id check */
            if
            :: ((ticket_state == RESERVED || ticket_state == PAID || ticket_state == DELIVERED) && b < N) ->
                cancelAccepted = true;
                reserved_by = NO_BUYER;
                current_res_id = NO_RES;
                ticket_state = AVAILABLE;
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
                ticket_state = DELIVERED;
                seller_ch ! deliver_ok
            :: else ->
                seller_ch ! deliver_fail
            fi

        :: msg == confirm ->
            /* Buggy: omits b == buyer_of_sale and r == current_res_id checks */
            if
            :: (ticket_state == DELIVERED && b < N) ->
                deliveryConfirmed = true;
                confirmAccepted = true;
                confirmed_by = b;
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
            /* Buggy: unconditionally sets buyer_of_sale and PAID without checking stale res_id/state */
            buyer_of_sale = b;
            ticket_state = PAID;
            if
            :: (b < N) -> buyer_ch[b] ! pay_ok(r)
            :: else -> skip
            fi

        :: msg == charge_fail ->
            if
            :: (b < N) -> buyer_ch[b] ! pay_fail(r)
            :: else -> skip
            fi

        :: msg == refund_ok ->
            ticket_state = REFUNDED

        :: msg == payout_ok ->
            ticket_state = SETTLED;
            if
            :: (b < N) -> buyer_ch[b] ! confirm_ok(r)
            :: else -> skip
            fi

        :: else -> skip
        fi

    /* Abstract RESERVED timeout */
    :: (ticket_state == RESERVED) ->
        reserved_by = NO_BUYER;
        current_res_id = NO_RES;
        ticket_state = AVAILABLE

    /* Abstract PAID timeout */
    :: (ticket_state == PAID) ->
        pay_req ! refund(buyer_of_sale, current_res_id)
    od;

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
