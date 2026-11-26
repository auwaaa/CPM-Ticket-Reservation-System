/*
 * 01_naive.pml - Initial naive model of the Ticket Reservation System
 * Assembled by M3 to expose concurrency flaws & capture counterexamples for S1, S5, S8, S9.
 *
 * Deliberate Defects Injected (vs. 02_final.pml):
 *   1. Breaks S1 (Double-sale): charge_ok -> PAID lacks atomic state/res_id check,
 *      allowing multiple charges or stale charges to overwrite buyer_of_sale & increment sale_count.
 *   2. Breaks S5 (Illegal cancel/confirm): cancel omits ticket_state == RESERVED guard,
 *      allowing cancellation after payment/delivery.
 *   3. Breaks S8 (Stale-charge money leak): omits r == current_res_id check and stale-charge
 *      refund handling, leaving held_cnt > 0 at terminal states or losing escrow invariants.
 *   4. Breaks S9 (Missing authorization): omits b == reserved_by / b == buyer_of_sale check
 *      on pay, cancel, and confirm so any Buyer can hijack another Buyer's flow.
 */

#include "defs.pml"

/* === M1 SECTION START: Naive Marketplace (Unguarded) === */
proctype Marketplace() {
    mtype:msg msg;
    byte b;
    byte r;

end_marketplace:
    do
    :: is_terminal -> break

    :: mkt_req ? msg, b, r ->
        if
        :: msg == reserve ->
            if
            :: ticket_state == AVAILABLE ->
                /* Defect: non-atomic reserve + missing cancelAccepted reset */
                current_res_id = next_res_id;
                if
                :: next_res_id == 255 -> next_res_id = 1
                :: else -> next_res_id++
                fi;
                reserved_by = b;
                ticket_state = RESERVED;
                buyer_ch[b] ! reserve_ok(current_res_id)
            :: else ->
                buyer_ch[b] ! reserve_fail(NO_RES)
            fi

        :: msg == pay ->
            /* Defect (S9/S8): missing b == reserved_by && r == current_res_id && state check */
            if
            :: (ticket_state == RESERVED || ticket_state == AVAILABLE) ->
                pay_req ! charge(b, r)
            :: else ->
                buyer_ch[b] ! pay_fail(r)
            fi

        :: msg == cancel ->
            /* Defect (S5/S9): missing b == reserved_by && ticket_state == RESERVED guard */
            if
            :: (ticket_state == RESERVED || ticket_state == PAID || ticket_state == DELIVERED) ->
                cancelAccepted = true;
                reserved_by = NO_BUYER;
                current_res_id = NO_RES;
                ticket_state = AVAILABLE;
                buyer_ch[b] ! cancel_ok(r)
            :: else ->
                buyer_ch[b] ! cancel_fail(r)
            fi

        :: msg == deliver ->
            if
            :: ticket_state == PAID ->
                ever_delivered = true;
                ticket_state = DELIVERED;
                seller_ch ! deliver_ok
            :: else ->
                seller_ch ! deliver_fail
            fi

        :: msg == confirm ->
            /* Defect (S9): missing b == buyer_of_sale && r == current_res_id guard */
            if
            :: ticket_state == DELIVERED ->
                deliveryConfirmed = true;
                confirmAccepted = true;
                confirmed_by = b;
                pay_req ! payout(b, r);
                pay_resp ? payout_ok(_, _);
                ticket_state = SETTLED;
                buyer_ch[b] ! confirm_ok(r)
            :: else ->
                buyer_ch[b] ! confirm_fail(r)
            fi

        :: msg == withdraw ->
            if
            :: ticket_state == AVAILABLE ->
                ticket_state = WITHDRAWN;
                seller_ch ! withdraw_ok
            :: else ->
                seller_ch ! withdraw_fail
            fi
        fi

    :: pay_resp ? msg, b, r ->
        if
        :: msg == charge_ok ->
            /* Defect (S1/S8): omits r == current_res_id check & omits stale-charge refund */
            if
            :: (ticket_state == RESERVED || ticket_state == PAID) ->
                buyer_of_sale = b;
                ever_paid = true;
                sale_count++;
                ticket_state = PAID;
                buyer_ch[b] ! pay_ok(r)
            :: else ->
                /* Stale charge_ok silently dropped without issuing refund -> S8 leak! */
                buyer_ch[b] ! pay_fail(r)
            fi
        :: msg == charge_fail ->
            buyer_ch[b] ! pay_fail(r)
        :: else -> skip
        fi

    :: ticket_state == RESERVED ->
        /* Abstract RESERVED timeout (does NOT wait for or refund in-flight charge) */
        reserved_by = NO_BUYER;
        current_res_id = NO_RES;
        ticket_state = AVAILABLE

    :: ticket_state == PAID ->
        /* Abstract PAID non-delivery timeout */
        pay_req ! refund(buyer_of_sale, current_res_id);
        pay_resp ? refund_ok(_, _);
        sale_refunded = true;
        ticket_state = REFUNDED
    od
}
/* === M1 SECTION END: Naive Marketplace === */

/* === M2 SECTION START: Participants (Seller & Buyer for Naive Model) === */
proctype Seller() {
end_seller:
    do
    :: is_terminal -> break
    :: ticket_state == AVAILABLE ->
        mkt_req ! withdraw(0, NO_RES);
        seller_ch ? _
    :: ticket_state == PAID ->
        mkt_req ! deliver(0, NO_RES);
        seller_ch ? _
    od
}

proctype Buyer(byte id) {
    byte attempts = 0;
    mtype:msg reply;
    byte my_res = NO_RES;
    byte tmp_r = NO_RES;
    bool spoofed = false;

    do
    :: is_terminal -> break

    :: ticket_state == DELIVERED && buyer_of_sale == id ->
        /* Assumption A9: winning buyer MUST confirm delivery — no abandonment allowed */
        mkt_req ! confirm(id, my_res);
        buyer_ch[id] ? reply, tmp_r;
        if
        :: reply == confirm_ok -> break
        :: else -> skip   /* retry on fail */
        fi

    :: attempts < K && !is_terminal && buyer_of_sale != id ->
        attempts++;
        mkt_req ! reserve(id, NO_RES);
        buyer_ch[id] ? reply, my_res;
        if
        :: reply == reserve_ok ->
            if
            :: /* Pay path */
               mkt_req ! pay(id, my_res);
               buyer_ch[id] ? reply, tmp_r;
               if
               :: reply == pay_ok -> skip   /* A9 confirm handled by outer loop guard */
               :: else -> skip
               fi
            :: /* Cancel path */
               mkt_req ! cancel(id, my_res);
               buyer_ch[id] ? reply, tmp_r
            :: /* Pre-PAID abandonment (Defect for S1/S9: stale res_id stays active) */
               skip
            fi
        :: else -> skip
        fi

    :: !spoofed && !is_terminal && reserved_by != id && buyer_of_sale != id ->
        /* Spoofed / unauthorized request branch (exposes S5/S9 defects in naive model) */
        spoofed = true;
        if
        :: mkt_req ! pay(id, 1); buyer_ch[id] ? reply, tmp_r
        :: mkt_req ! cancel(id, 1); buyer_ch[id] ? reply, tmp_r
        :: mkt_req ! confirm(id, 1); buyer_ch[id] ? reply, tmp_r
        fi

    :: attempts >= K && spoofed && buyer_of_sale != id && !is_terminal -> break

    od
}
/* === M2 SECTION END: Participants === */

/* === M3 SECTION START: PaymentService === */
proctype PaymentService() {
    mtype:msg cmd;
    byte b;
    byte r;

end_payment:
    do
    :: pay_req ? cmd, b, r ->
        if
        :: cmd == charge ->
            if
            :: atomic {
                   charged_cnt++;
                   held_cnt++;
               }
               pay_resp ! charge_ok(b, r)
            :: pay_resp ! charge_fail(b, r)
            fi
        :: cmd == payout ->
            atomic {
                if
                :: held_cnt > 0 ->
                    held_cnt--;
                    paidOut_cnt++
                :: else -> skip
                fi
            }
            pay_resp ! payout_ok(b, r)
        :: cmd == refund ->
            atomic {
                if
                :: held_cnt > 0 ->
                    held_cnt--;
                    refunded_cnt++
                :: else -> skip
                fi
            }
            pay_resp ! refund_ok(b, r)
        fi
    od
}
/* === M3 SECTION END: PaymentService === */

/* === M1 SECTION START: Init === */
init {
    atomic {
        run Marketplace();
        run PaymentService();
        run Seller();
        byte i = 0;
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
ltl S1 {
    [] (
        (sale_count <= 1) &&
        (ticket_state == SETTLED -> (buyer_of_sale != NO_BUYER && confirmed_by == buyer_of_sale))
    )
}

ltl S2 {
    [] (
        (ticket_state == DELIVERED -> ever_paid) &&
        (ticket_state == SETTLED -> (ever_paid && ever_delivered && deliveryConfirmed))
    )
}

ltl S3 {
    [] (
        (ticket_state == SETTLED   -> [] (ticket_state == SETTLED)) &&
        (ticket_state == WITHDRAWN -> [] (ticket_state == WITHDRAWN)) &&
        (ticket_state == REFUNDED  -> [] (ticket_state == REFUNDED))
    )
}

ltl S4 {
    [] (
        ticket_state == WITHDRAWN ->
            (!ever_paid && !ever_delivered && reserved_by == NO_BUYER && buyer_of_sale == NO_BUYER)
    )
}

ltl S5 {
    [] (
        !(cancelAccepted && confirmAccepted) &&
        (ever_paid -> !cancelAccepted)
    )
}

ltl S6 {
    [] (
        (paidOut_cnt <= 1) &&
        (ticket_state == SETTLED  -> (paidOut_cnt == 1 && !sale_refunded)) &&
        (ticket_state == REFUNDED -> (paidOut_cnt == 0 && sale_refunded))
    )
}

ltl S7 {
    [] (
        (paidOut_cnt + refunded_cnt <= charged_cnt) &&
        (held_cnt <= charged_cnt) &&
        ((ticket_state == PAID || ticket_state == DELIVERED) -> charged_cnt >= 1)
    )
}

ltl S8 {
    [] (
        (charged_cnt == held_cnt + paidOut_cnt + refunded_cnt) &&
        (is_terminal -> held_cnt == 0)
    )
}

ltl S9 {
    [] (
        (confirmAccepted -> (confirmed_by == buyer_of_sale && buyer_of_sale != NO_BUYER)) &&
        ((ticket_state == PAID || ticket_state == DELIVERED || ticket_state == SETTLED) -> buyer_of_sale != NO_BUYER)
    )
}

ltl L1 {
    [] (ticket_state == PAID -> <> (ticket_state == SETTLED || ticket_state == REFUNDED))
}

ltl L2 {
    [] (ticket_state == DELIVERED -> <> (ticket_state == SETTLED))
}

ltl L3 {
    <> (ticket_state == SETTLED || ticket_state == WITHDRAWN || ticket_state == REFUNDED)
}
/* === M3 SECTION END: LTL Specifications (S1-S9, L1-L3) === */
