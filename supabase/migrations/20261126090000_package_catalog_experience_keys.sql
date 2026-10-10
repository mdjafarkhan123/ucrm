-- Multi-industry foundation B3: Uplift's package list says which kinds of business each published package is
-- sold to, so the Prospects page can offer only packages that fit an application's confirmed kind of business.
-- Same function as 20261006100709, with experience_keys added to the published edition.

create or replace function public.owner_package_catalog()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select coalesce(jsonb_agg(row_json order by display_order, created_at), '[]'::jsonb)
	from (
		select
			p.display_order,
			p.created_at,
			jsonb_build_object(
				'id', p.id,
				'slug', p.slug,
				'visibility', p.visibility,
				'display_order', p.display_order,
				'archived_at', p.archived_at,
				'created_at', p.created_at,
				'website_update_pending_since', p.website_update_pending_since,
				'website_changes', case when p.website_update_pending_since is null then '[]'::jsonb else (
					select coalesce(jsonb_agg(jsonb_build_object(
						'event_type', ev.event_type, 'edition_number', ev.edition_number, 'detail', ev.detail,
						'created_at', ev.created_at
					) order by ev.created_at), '[]'::jsonb)
					from public.package_catalog_events ev
					where ev.package_id = p.id and ev.created_at >= p.website_update_pending_since
						and ev.event_type in ('published', 'visibility_changed', 'moved', 'archived', 'restored')
				) end,
				'draft', (
					select jsonb_build_object(
						'edition_id', d.id, 'revision', d.revision, 'name', d.name,
						'monthly_price_usd_cents', d.monthly_price_usd_cents,
						'yearly_price_usd_cents', d.yearly_price_usd_cents,
						'updated_at', d.updated_at
					)
					from public.package_editions d
					where d.package_id = p.id and d.status = 'draft'
				),
				'published', (
					select jsonb_build_object(
						'edition_id', pe.id, 'edition_number', pe.edition_number, 'name', pe.name,
						'monthly_price_usd_cents', pe.monthly_price_usd_cents,
						'yearly_price_usd_cents', pe.yearly_price_usd_cents,
						'published_at', pe.published_at,
						'experience_keys', to_jsonb(pe.experience_keys)
					)
					from public.package_editions pe
					where pe.package_id = p.id and pe.status = 'published'
				),
				'organization_count', private.package_customer_count(p.id),
				'delete_blocker', private.package_delete_blocker(p.id)
			) as row_json
		from public.packages p
	) as rows;
$$;
