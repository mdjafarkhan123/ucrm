-- Package builder P14: the platform-wide automation safety values Jafar agreed on 2026-09-30. They apply to
-- every business alike, whatever its package, so no contractor can build an automation that spams customers.
-- The longest single wait follows Jobber's 90-day cap on follow-ups. Enrollments already running keep the
-- end date they started with; new ones end after 180 days.

update public.platform_automation_safety_limits as s
set limit_state = 'numeric', limit_value = v.value, updated_at = now()
from (values
	('automation_max_conditions_per_recipe', 6),
	('automation_max_steps_per_recipe', 10),
	('automation_max_customer_messages_per_enrollment', 5),
	('automation_min_customer_message_spacing_minutes', 60),
	('automation_max_delay_days', 90),
	('automation_max_enrollment_duration_days', 180)
) as v (limit_key, value)
where s.limit_key = v.limit_key;
