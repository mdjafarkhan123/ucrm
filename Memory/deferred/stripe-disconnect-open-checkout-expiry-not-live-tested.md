# Disconnecting Stripe expires open checkouts: code-complete, never live-tested

- **Priority:** P2
- **Why postponed:** Jafar deferred it (online-payments Part 5) because testing needs Raad LTD's test Stripe key re-pasted by hand afterward.
- **Reactivate when:** A real contractor disconnects Stripe with a checkout open, or before the first paying client goes live.
- **Constraint:** Test on a throwaway sandbox connection, not Raad LTD's.
- **Pointer:** src/lib/server/payments/stripe-connection.ts and the disconnect route.
