-- Advisor-flagged FK without a covering index. Small and cheap: this table sees far fewer rows than the
-- checkouts it refunds, and this supports a plausible future "refunds I issued" read model.
create index payment_stripe_refunds_requested_by_idx
  on public.payment_stripe_refunds (requested_by)
  where requested_by is not null;
