-- Client onboarding A5b: a condition missing a part (say `values`) made the shape check unknown rather than
-- false, and an unknown check passes. Each condition now counts as valid only when it is definitely valid.

create or replace function private.setup_show_if_shape_ok(rule jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
	select rule is null or (
		jsonb_typeof(rule) = 'array'
		and jsonb_array_length(rule) between 1 and 5
		and not exists (
			select 1
			from jsonb_array_elements(rule) as c(value)
			where not coalesce(
				jsonb_typeof(c.value) = 'object'
				and (
					(
						(select count(*) from jsonb_object_keys(c.value)) = 1
						and jsonb_typeof(c.value -> 'service_key') = 'string'
						and (c.value ->> 'service_key') ~ '^[a-z][a-z0-9_]{1,59}$'
					)
					or (
						(select count(*) from jsonb_object_keys(c.value)) = 2
						and jsonb_typeof(c.value -> 'fact_key') = 'string'
						and (c.value ->> 'fact_key') ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'
						and char_length(c.value ->> 'fact_key') <= 80
						and jsonb_typeof(c.value -> 'values') = 'array'
						and jsonb_array_length(c.value -> 'values') between 1 and 60
						and not exists (
							select 1
							from jsonb_array_elements(c.value -> 'values') as v(value)
							where jsonb_typeof(v.value) <> 'string' or char_length(v.value #>> '{}') not between 1 and 120
						)
					)
				),
				false
			)
		)
	);
$$;

revoke all on function private.setup_show_if_shape_ok(jsonb) from public, anon, authenticated;
