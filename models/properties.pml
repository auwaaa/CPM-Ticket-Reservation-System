/*
 * properties.pml - LTL specification S1-S7 (safety) and L1-L5 (liveness)
 * Ticket Reservation System (CPM Group 2) — Owner: M3
 *
 * Source of truth: docs/revised_project_proposal.md, Section 8.
 * Included by BOTH 01_naive.pml and 02_final.pml, so the buggy and the
 * hardened model are judged by exactly the same formulas.
 *
 * Conventions
 *  - No X (next) operator anywhere: every formula is stutter-invariant, so
 *    SPIN's partial-order reduction stays sound (spinroot ltl.html).
 *  - Safety claims have the shape [] P (S3 nests a [] inside). SPIN turns
 *    their negation into a never claim whose violation is an assert, so they
 *    are verified in a -DSAFETY build: ./pan -N S1 ... ./pan -N S7
 *  - Liveness claims have the response shape [] (P -> <> Q) and are verified
 *    with acceptance-cycle search under weak fairness: ./pan -a -f -N L1 ...
 *  - Any ltl block disables pan's deadlock check ("invalid end states -
 *    (disabled by never claim)"). Check deadlocks separately with a build
 *    compiled with -DNOCLAIM.
 */

/* ---------------------------------------------------------------- Safety -- */

/* S1 At-Most-Once Sale: PAID is entered at most once, and once it has been
 * entered the sale's (buyer, reservation) pair never changes. */
ltl S1 {
    [] ( (sale_count <= 1) &&
         (ever_paid -> (current_buyer == sale_buyer && current_res_id == sale_res_id &&
                        sale_buyer != NO_BUYER && sale_res_id != NO_RES)) )
}

/* S2 Mutual Exclusion of Reservations: a reservation is only granted from
 * AVAILABLE with no holder, and a RESERVED listing always has exactly one
 * well-defined holder (b, r). */
ltl S2 {
    [] ( !violation_mutex_reserve &&
         (ticket_state == RESERVED -> (current_buyer != NO_BUYER && current_res_id != NO_RES)) )
}

/* S3 Withdrawal Integrity: withdraw is accepted only from AVAILABLE; a
 * WITHDRAWN listing was never sold or delivered, has no holder, and stays
 * WITHDRAWN forever. */
ltl S3 {
    [] ( !violation_bad_withdraw &&
         (ticket_state == WITHDRAWN ->
              (!ever_paid && !ever_delivered && current_buyer == NO_BUYER &&
               [] (ticket_state == WITHDRAWN))) )
}

/* S4 No Stale Charge Acceptance: a charge_ok is only accepted (-> PAID) if it
 * matches the active (b, r) in RESERVED, and the seller is only ever paid
 * for the sale's own reservation. A stale charge may sit in escrow until it
 * is refunded (that is L4, not a violation of S4). */
ltl S4 {
    [] ( !violation_stale_accept &&
         (payout_res != NO_RES -> payout_res == sale_res_id) )
}

/* S5 Confirmed Delivery Before Payout: whenever the seller holds money, the
 * ticket was delivered, delivery was confirmed (explicitly or by
 * confirm_timeout), and the listing is SETTLED. */
ltl S5 {
    [] ( seller_bal > 0 -> (ever_delivered && deliveryConfirmed && ticket_state == SETTLED) )
}

/* S6 Single Settlement per Charge: no payout/refund is ever attempted on a
 * charge that is not HELD (no duplicates, no unbacked settlements), hence
 * the seller is paid at most once. */
ltl S6 {
    [] ( !violation_dup_settlement && seller_bal <= 1 )
}

/* S7 Strict Money Conservation: sum(balance) + escrow + seller_bal == B0 and
 * no account is negative, in every reachable state. */
ltl S7 {
    [] LEDGER_OK
}

/* -------------------------------------------------------------- Liveness -- */

/* L1 Reservation Termination: RESERVED is always eventually left. */
ltl L1 {
    [] ( ticket_state == RESERVED -> <> (ticket_state == AVAILABLE || ticket_state == PAID) )
}

/* L2 Non-Delivery Refund: a PAID listing is either eventually delivered, or
 * it eventually reaches REFUNDED with the buyer's charge actually refunded. */
ltl L2 {
    [] ( ticket_state == PAID ->
         <> (ever_delivered ||
             (ticket_state == REFUNDED && charge_status[sale_res_id] == CHG_REFUNDED)) )
}

/* L3 Escrow Resolution: every held charge is eventually paid out or refunded. */
ltl L3 {
    [] ( escrow > 0 -> <> (escrow == 0) )
}

/* L4 Late-Payment Refund: every stale charge_ok eventually has its refund
 * completed (refund_ok received). */
ltl L4 {
    [] ( stale_refund_pending > 0 -> <> (stale_refund_pending == 0) )
}

/* L5 Post-Sale Termination: once PAID, the listing eventually reaches
 * SETTLED or REFUNDED. */
ltl L5 {
    [] ( ticket_state == PAID -> <> (ticket_state == SETTLED || ticket_state == REFUNDED) )
}
