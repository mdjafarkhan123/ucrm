-- Rebilling a voided invoice failed with "A voided invoice cannot be changed."
--
-- The identity guard freezes a voided bill against every change except being marked as replaced, by comparing
-- the whole row before and after with the three replacement columns and updated_at left out. Setting
-- replaced_at also flips the stored, automatically calculated is_effective_receivable column, and that
-- column was not left out, so the one allowed change looked like a forbidden one. The column is calculated
-- only from voided_at, issued_at, recognized_at, written_off_at and replaced_at, and the guard already blocks
-- the first three from changing and compares the fourth, so leaving it out of the comparison loosens nothing.

CREATE OR REPLACE FUNCTION private.invoices_guard_identity()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  if new.organization_id is distinct from old.organization_id then
    raise exception 'An invoice cannot be moved to another organization.' using errcode = 'check_violation';
  end if;
  if new.client_id is distinct from old.client_id then
    raise exception 'An invoice cannot be moved to another client.' using errcode = 'check_violation';
  end if;
  if new.invoice_number is distinct from old.invoice_number then
    raise exception 'An invoice number cannot be changed.' using errcode = 'check_violation';
  end if;
  if new.root_invoice_id is distinct from old.root_invoice_id
     or new.predecessor_invoice_id is distinct from old.predecessor_invoice_id then
    raise exception 'An invoice cannot be moved to another correction chain.'
      using errcode = 'check_violation';
  end if;
  if new.currency_code is distinct from old.currency_code and old.document_frozen_at is not null then
    raise exception 'An issued invoice''s currency cannot be changed.' using errcode = 'check_violation';
  end if;
  if old.issued_at is not null and new.issued_at is distinct from old.issued_at then
    raise exception 'An invoice that has been issued cannot be un-issued.' using errcode = 'check_violation';
  end if;
  if old.recognized_at is not null and new.recognized_at is distinct from old.recognized_at then
    raise exception 'A settled invoice cannot be un-settled.' using errcode = 'check_violation';
  end if;
  if old.voided_at is not null then
    if new.voided_at is distinct from old.voided_at then
      raise exception 'A voided invoice cannot be reopened.' using errcode = 'check_violation';
    end if;
    if to_jsonb(new) - 'replaced_at' - 'replaced_by_invoice_id' - 'frozen_status_label' - 'updated_at'
         - 'is_effective_receivable'
       is distinct from
       to_jsonb(old) - 'replaced_at' - 'replaced_by_invoice_id' - 'frozen_status_label' - 'updated_at'
         - 'is_effective_receivable' then
      raise exception 'A voided invoice cannot be changed.' using errcode = 'check_violation';
    end if;
  end if;
  if old.replaced_at is not null then
    if new.replaced_at is distinct from old.replaced_at
       or new.replaced_by_invoice_id is distinct from old.replaced_by_invoice_id
       or new.frozen_status_label is distinct from old.frozen_status_label then
      raise exception 'A replaced invoice''s history cannot be rewritten.'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$function$;
