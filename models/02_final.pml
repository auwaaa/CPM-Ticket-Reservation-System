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
    skip;
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
