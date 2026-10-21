import {
	MARKETING_GROUP_RULE_CONDITIONS,
	type MarketingGroupRuleConditionKey,
	type MarketingGroupRules
} from './customer-groups';

// One short phrase per condition a saved customer group holds, read after "Matches customers who": the
// New campaign Customers step shows them as chips under the group picker, so the contractor sees what the
// group does without opening it. A condition that only holds ids (tags, hand-picked customers) is said by
// its count; services use their names once `serviceNames` has them.
export type GroupRuleChip = { key: MarketingGroupRuleConditionKey; text: string };

function count(n: number, one: string, many: string) {
	return `${n} ${n === 1 ? one : many}`;
}

// "Austin, Dallas" or "Austin, Dallas +3" once a list runs long.
function nameList(values: string[], shown = 2) {
	const head = values.slice(0, shown).join(', ');
	return values.length > shown ? `${head} +${values.length - shown}` : head;
}

// The rules store days; people think in weeks, months and years (180 days reads as 6 months).
function duration(days: number) {
	if (days % 365 === 0) return count(days / 365, 'year', 'years');
	if (days % 30 === 0) return count(days / 30, 'month', 'months');
	if (days % 7 === 0) return count(days / 7, 'week', 'weeks');
	return count(days, 'day', 'days');
}

export function groupRuleChips(
	rules: MarketingGroupRules,
	serviceNames: Record<string, string> = {}
): GroupRuleChip[] {
	const chips: GroupRuleChip[] = [];
	for (const { key } of MARKETING_GROUP_RULE_CONDITIONS) {
		const text = chipText(key, rules, serviceNames);
		if (text) chips.push({ key, text });
	}
	return chips;
}

function chipText(
	key: MarketingGroupRuleConditionKey,
	rules: MarketingGroupRules,
	serviceNames: Record<string, string>
): string | null {
	switch (key) {
		case 'lifecycle': {
			const states = rules.lifecycle ?? [];
			if (states.length === 0) return null;
			return states.length === 2 ? 'Are leads or customers' : `Are ${states[0]}s`;
		}
		case 'tags': {
			const n = rules.tags?.length ?? 0;
			if (n === 0) return null;
			return n === 1 ? 'Have the chosen tag' : `Have any of ${n} tags`;
		}
		case 'cities':
			return rules.cities?.length ? `Are in ${nameList(rules.cities)}` : null;
		case 'lead_sources':
			return rules.lead_sources?.length ? `Came from ${nameList(rules.lead_sources)}` : null;
		case 'services': {
			const ids = rules.services ?? [];
			if (ids.length === 0) return null;
			const names = ids.map((id) => serviceNames[id]).filter(Boolean);
			return names.length === ids.length
				? `Used ${nameList(names)}`
				: `Used ${count(ids.length, 'service', 'services')}`;
		}
		case 'work_type':
			return rules.work_type
				? rules.work_type === 'one_off'
					? 'Have one-off work'
					: 'Have recurring work'
				: null;
		case 'last_completed_job': {
			const job = rules.last_completed_job;
			if (!job) return null;
			if (job.mode === 'never') return 'Have never had a completed job';
			return job.mode === 'within_days'
				? `Last job within ${duration(job.days)}`
				: `Last job over ${duration(job.days)} ago`;
		}
		case 'upcoming_work':
			return rules.upcoming_work === undefined
				? null
				: rules.upcoming_work
					? 'Have upcoming work'
					: 'Have no upcoming work';
		case 'include_client_ids': {
			const n = rules.include_client_ids?.length ?? 0;
			return n ? `Always include ${count(n, 'customer', 'customers')}` : null;
		}
		case 'exclude_client_ids': {
			const n = rules.exclude_client_ids?.length ?? 0;
			return n ? `Always exclude ${count(n, 'customer', 'customers')}` : null;
		}
	}
}
