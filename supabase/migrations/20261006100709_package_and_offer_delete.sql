-- Package and offer delete. A package or an offer nobody ever used can be deleted; anything with customer
-- history stays and can only be archived. The catalog and offer lists say why a delete is refused, so the
-- menu can explain it instead of hiding it.
--
-- A published edition is frozen by a trigger so customer terms can never be erased. Deleting an unused
-- package is the one allowed exception, and only the delete function below can open it, for that package only.
begin;

create or replace function private.prevent_frozen_package_edition_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
	if tg_op = 'DELETE' then
		if old.status <> 'draft'
			and coalesce(current_setting('private.deleting_package_id', true), '') <> old.package_id::text then
			raise exception 'A published package edition cannot be deleted.' using errcode = 'check_violation';
		end if;
		return old;
	end if;

	if old.status = 'draft' then
		return new;
	end if;

	if old.status = 'published' and new.status = 'superseded'
		and (to_jsonb(new) - array['status', 'superseded_at', 'updated_at'])
			= (to_jsonb(old) - array['status', 'superseded_at', 'updated_at']) then
		return new;
	end if;

	raise exception 'A published package edition cannot be changed. Publish a new edition instead.'
		using errcode = 'check_violation';
end;
$$;

-- Why this package cannot be deleted, in words for Jafar, or null when nothing was ever built on it.
create or replace function private.package_delete_blocker(target_package_id uuid)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
	customers integer;
	offer_name text;
begin
	select count(distinct a.organization_id)::integer into customers
	from public.organization_package_agreements a
	join public.package_editions e on e.id = a.edition_id
	where e.package_id = target_package_id;
	if customers > 0 then
		return format('%s %s on this package, or %s been. Archive it instead so their history stays.',
			customers, case when customers = 1 then 'customer is' else 'customers are' end,
			case when customers = 1 then 'has' else 'have' end);
	end if;

	if exists (
		select 1 from public.platform_onboarding_applications ap
		join public.package_editions e on e.id = ap.package_edition_id
		where e.package_id = target_package_id
	) then
		return 'A customer application chose this package. Archive it instead so that record stays.';
	end if;

	select o.name into offer_name
	from public.package_offer_packages op
	join public.package_offers o on o.id = op.offer_id
	where op.package_id = target_package_id
	order by o.created_at
	limit 1;
	if offer_name is not null then
		return format('The offer “%s” includes this package. Take it off that offer first.', offer_name);
	end if;

	if exists (select 1 from public.platform_email_template_packages t where t.package_id = target_package_id) then
		return 'An email template is limited to this package. Change that template first.';
	end if;

	if private.package_is_listed(target_package_id) then
		return 'This package is public on your website. Make it private or archive it first.';
	end if;

	return null;
end;
$$;

-- Why this offer cannot be deleted, or null when no customer ever claimed it. A released claim still counts:
-- it is the record of a discount someone was given.
create or replace function private.package_offer_delete_blocker(target_offer_id uuid)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
	customers integer;
begin
	select count(distinct c.organization_id)::integer into customers
	from public.package_offer_claims c where c.offer_id = target_offer_id;
	if customers > 0 then
		return format('%s %s claimed this offer, so it stays on record. Archive it instead.',
			customers, case when customers = 1 then 'customer has' else 'customers have' end);
	end if;
	return null;
end;
$$;

create or replace function public.delete_package(target_package_id uuid, actor_owner_email text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	blocker text;
	snapshot jsonb;
begin
	perform 1 from public.packages p where p.id = target_package_id for update;
	if not found then
		raise exception 'Package was not found.' using errcode = 'P0002';
	end if;
	-- Lock the editions too, so a customer cannot be put on one between the check and the delete.
	perform 1 from public.package_editions e where e.package_id = target_package_id for update;

	blocker := private.package_delete_blocker(target_package_id);
	if blocker is not null then
		raise exception '%', blocker using errcode = 'check_violation';
	end if;

	select jsonb_build_object(
		'slug', p.slug,
		'name', (select e.name from public.package_editions e where e.package_id = p.id
			order by (e.status = 'published') desc, e.created_at desc limit 1),
		'editions', (select count(*) from public.package_editions e where e.package_id = p.id),
		'archived', p.archived_at is not null
	) into snapshot
	from public.packages p where p.id = target_package_id;

	perform set_config('private.deleting_package_id', target_package_id::text, true);
	delete from public.package_editions where package_id = target_package_id;
	delete from public.packages where id = target_package_id;
	perform set_config('private.deleting_package_id', '', true);

	insert into public.platform_owner_audit_events (
		actor_owner_email, event_type, target_type, target_key, before_state
	) values (
		nullif(trim(coalesce(actor_owner_email, '')), ''), 'package.deleted', 'package',
		target_package_id::text, snapshot
	);

	return jsonb_build_object('deleted', true);
end;
$$;

create or replace function public.delete_package_offer(offer_id uuid, actor_owner_email text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	target public.package_offers;
	blocker text;
begin
	select o.* into target from public.package_offers o
	where o.id = delete_package_offer.offer_id for update;
	if target.id is null then
		raise exception 'That offer was not found.' using errcode = 'foreign_key_violation';
	end if;

	blocker := private.package_offer_delete_blocker(target.id);
	if blocker is not null then
		raise exception '%', blocker using errcode = 'check_violation';
	end if;

	delete from public.package_offers o where o.id = target.id;

	insert into public.platform_owner_audit_events (
		actor_owner_email, event_type, target_type, target_key, before_state
	) values (
		nullif(trim(coalesce(delete_package_offer.actor_owner_email, '')), ''), 'package_offer.deleted',
		'package_offer', target.id::text,
		jsonb_build_object('name', target.name, 'apply_mode', target.apply_mode, 'code', target.code)
	);

	return jsonb_build_object('deleted', true);
end;
$$;

-- The two lists gain one field each: why a delete would be refused (null when it is allowed).
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
						'published_at', pe.published_at
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

create or replace function public.owner_package_offers()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select coalesce(jsonb_agg(jsonb_build_object(
		'id', o.id, 'name', o.name, 'apply_mode', o.apply_mode, 'code', o.code,
		'discount_kind', o.discount_kind, 'percent_off', o.percent_off, 'amount_off_usd_cents', o.amount_off_usd_cents,
		'applies_to_monthly', o.applies_to_monthly, 'applies_to_yearly', o.applies_to_yearly,
		'monthly_periods', o.monthly_periods, 'customer_eligibility', o.customer_eligibility,
		'claim_starts_at', o.claim_starts_at, 'claim_ends_at', o.claim_ends_at, 'redemption_cap', o.redemption_cap,
		'archived_at', o.archived_at, 'revision', o.revision, 'created_at', o.created_at, 'updated_at', o.updated_at,
		'status', case
			when o.archived_at is not null then 'archived'
			when o.claim_starts_at > now() then 'scheduled'
			when o.claim_ends_at is not null and o.claim_ends_at <= now() then 'ended'
			when o.redemption_cap is not null and private.package_offer_claim_count(o.id) >= o.redemption_cap then 'full'
			else 'open'
		end,
		'terms_locked', exists (select 1 from public.package_offer_claims c where c.offer_id = o.id),
		'claim_count', private.package_offer_claim_count(o.id),
		'delete_blocker', private.package_offer_delete_blocker(o.id),
		'package_ids', coalesce((select jsonb_agg(op.package_id) from public.package_offer_packages op
			where op.offer_id = o.id), '[]'::jsonb),
		'claims', coalesce((
			select jsonb_agg(jsonb_build_object(
				'id', c.id, 'organization_id', c.organization_id, 'organization_name', org.name,
				'method', c.method, 'honored', c.honored, 'claimed_at', c.created_at, 'released_at', c.released_at,
				'actor_owner_email', c.actor_owner_email) order by c.created_at desc)
			from public.package_offer_claims c
			join public.organizations org on org.id = c.organization_id
			where c.offer_id = o.id
		), '[]'::jsonb)
	) order by o.archived_at nulls first, o.created_at desc), '[]'::jsonb)
	from public.package_offers o;
$$;

revoke all on function private.package_delete_blocker(uuid) from public, anon, authenticated;
revoke all on function private.package_offer_delete_blocker(uuid) from public, anon, authenticated;
revoke all on function public.delete_package(uuid, text) from public, anon, authenticated;
revoke all on function public.delete_package_offer(uuid, text) from public, anon, authenticated;

commit;
