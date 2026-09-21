-- Contractor Settings Part 5A found this while adding the missing pgTAP coverage for the invoice-terms
-- commands: `20260904170000_invoice_terms_billing_seam_and_permissions.sql` pointed every organization that
-- existed at the time at the protected "Due on receipt" term with a one-time backfill UPDATE, but nothing
-- keeps doing that for an organization created afterward. Every real organization today predates that
-- migration, so nothing has broken yet -- private.resolve_client_payment_term's own last-resort lookup means
-- invoices still resolve a real due date either way -- but a new organization now stores two null defaults,
-- which is what a Settings screen would have to show, and is a worse starting state than every other
-- organization has.
--
-- Fix at the row that is actually missing the value, not the organizations-table trigger that already seeds
-- the terms: a BEFORE INSERT trigger on organization_settings itself is independent of trigger firing order
-- on organizations (there are three AFTER INSERT triggers there already, alphabetically ordered, and
-- organizations_create_settings does not reliably run after organizations_create_invoice_payment_terms).
-- This trigger seeds the terms itself if they are not there yet (idempotent, same as the existing seed
-- function already guarantees via ON CONFLICT DO NOTHING) so it works regardless of which order the other
-- triggers fire in, then points both defaults at the protected receipt term, same value the backfill chose.

create or replace function private.seed_invoice_defaults()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  receipt_term_id uuid;
begin
  perform private.seed_invoice_payment_terms(new.organization_id);

  select id into receipt_term_id
  from public.invoice_payment_terms
  where organization_id = new.organization_id and rule = 'on_receipt' and is_protected;

  if new.invoice_default_term_residential_id is null then
    new.invoice_default_term_residential_id := receipt_term_id;
  end if;
  if new.invoice_default_term_commercial_id is null then
    new.invoice_default_term_commercial_id := receipt_term_id;
  end if;

  return new;
end;
$$;

revoke all on function private.seed_invoice_defaults() from public;
revoke execute on function private.seed_invoice_defaults() from anon, authenticated;

create trigger organization_settings_seed_invoice_defaults
before insert on public.organization_settings
for each row execute function private.seed_invoice_defaults();

-- No backfill needed: every existing organization_settings row already has both defaults set, either by the
-- original migration's one-time UPDATE or (for anything created since) coincidentally by hand. This trigger
-- only closes the gap for organizations created from now on.
