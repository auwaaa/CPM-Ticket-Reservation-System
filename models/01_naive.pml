/*
 * 01_naive.pml - Initial naive model of the Ticket Reservation System
 * Expected to expose concurrency flaws / LTL violations for trail capture.
 */

#include "defs.pml"

/* TODO (M1): Implement Marketplace proctype (naive version without full guards) */
proctype Marketplace() {
    skip;
}

/* TODO (M2): Implement Seller proctype */
proctype Seller() {
    skip;
}

/* TODO (M2): Implement Buyer proctype (parameterized by byte id) */
proctype Buyer(byte id) {
    skip;
}

/* TODO (M3): Implement PaymentService proctype */
proctype PaymentService() {
    skip;
}

/* TODO (M1/M2/M3): Initialize Marketplace, PaymentService, Seller, and N Buyers */
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

/* TODO (M3): Add LTL properties S1-S9 (safety) and L1-L3 (liveness) */
