-- Quotes Part 6C: readiness gating and customer-facing deposit display.
--
-- Approval, deposit satisfaction, and Job readiness stay separate facts (contract's "Deposits and payment
-- schedules" section): a required deposit never blocks the customer's Approve, only `ready_for_job`. That
-- boolean is computed in the API from data it already fetches -- nothing stored here.
--
-- The one thing that does need a database change is the customer document itself: it withholds every
-- other piece of money behind `include_money`, and the required deposit follows the same rule. `satisfied`
-- reuses the exact "live, non-reversed received event" check `record_quote_deposit_event` already uses to
-- refuse a second recording -- one definition of "paid", not a second one that could drift from it.
create or replace function private.quote_customer_document(
  quote_row public.quotes,
  version_row public.quote_versions,
  recipient_name text,
  recipient_email text,
  include_money boolean
) returns jsonb
language sql
stable
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'quote', jsonb_build_object(
      'quote_number', quote_row.quote_number,
      'status', quote_row.status,
      'sent_at', quote_row.sent_at,
      'decision', quote_row.decision,
      'decided_at', quote_row.decided_at
    ),
    'recipient', jsonb_build_object(
      'name', recipient_name,
      'email', recipient_email
    ),
    'business', jsonb_build_object('name', version_row.organization_name),
    'document', jsonb_build_object(
      'version_number', version_row.version_number,
      'published_at', version_row.published_at,
      'currency_code', version_row.currency_code,
      'client_display_name', version_row.client_display_name,
      'service_address_line1', version_row.service_address_line1,
      'service_address_line2', version_row.service_address_line2,
      'service_city', version_row.service_city,
      'service_state_region', version_row.service_state_region,
      'service_postal_code', version_row.service_postal_code,
      'service_country', version_row.service_country,
      'introduction', version_row.introduction,
      'client_message', version_row.client_message,
      'contract_disclaimer', version_row.contract_disclaimer,
      'show_quantities', version_row.show_quantities,
      'show_unit_prices', version_row.show_unit_prices and include_money,
      'show_line_totals', version_row.show_line_totals and include_money,
      'show_totals', version_row.show_totals and include_money
    ),
    'lines', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', line.id, 'position', line.position, 'line_kind', line.line_kind,
            'selection_kind', line.selection_kind,
            'is_recommended', line.is_recommended, 'category', line.category,
            'name', line.name, 'description', line.description, 'unit_label', line.unit_label,
            'image_attachment_id', line.image_attachment_id
          )
          || case when version_row.show_quantities
               then jsonb_build_object('quantity', line.quantity) else '{}'::jsonb end
          || case when version_row.show_unit_prices and include_money
               then jsonb_build_object('unit_price_minor', line.unit_price_minor) else '{}'::jsonb end
          || case when version_row.show_line_totals and include_money
               then jsonb_build_object('line_total_minor', line.line_total_minor) else '{}'::jsonb end
          order by line.position, line.id
        )
        from public.quote_version_lines as line
        where line.organization_id = version_row.organization_id
          and line.quote_id = version_row.quote_id
          and line.quote_version_id = version_row.id
      ),
      '[]'::jsonb
    ),
    'attachments', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', version_attachment.attachment_id,
            'name', version_attachment.display_name,
            'mime_type', file.mime_type,
            'size_bytes', file.size_bytes
          )
          order by version_attachment.position, version_attachment.id
        )
        from public.quote_version_attachments as version_attachment
        join public.attachments as file on file.id = version_attachment.attachment_id
        where version_attachment.organization_id = version_row.organization_id
          and version_attachment.quote_id = version_row.quote_id
          and version_attachment.quote_version_id = version_row.id
          and version_attachment.customer_visible
      ),
      '[]'::jsonb
    ),
    'totals', case when version_row.show_totals and include_money then jsonb_build_object(
      'subtotal_minor', version_row.subtotal_minor,
      'discount_name', version_row.discount_name,
      'discount_minor', version_row.discount_minor,
      'tax_name', version_row.tax_name,
      'tax_rate_basis_points', version_row.tax_rate_basis_points,
      'tax_minor', version_row.tax_minor,
      'total_minor', version_row.total_minor
    ) else null end,
    'deposit', case
      when include_money and version_row.deposit_type is not null and version_row.deposit_required_minor > 0
      then jsonb_build_object(
        'required_minor', version_row.deposit_required_minor,
        'satisfied', exists (
          select 1 from public.quote_deposit_events received
          where received.organization_id = version_row.organization_id
            and received.quote_id = version_row.quote_id
            and received.quote_version_id = version_row.id
            and received.event_type = 'received'
            and not exists (
              select 1 from public.quote_deposit_events reversal
              where reversal.organization_id = received.organization_id
                and reversal.reversed_event_id = received.id
            )
        )
      )
      else null
    end
  );
$$;
