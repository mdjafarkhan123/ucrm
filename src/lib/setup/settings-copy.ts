// Client onboarding C5: what a client's accepted setup answers become in their CRM settings (plan §4, §10
// journey 6; Jafar's choices of 2026-10-05). Only built-in questions are read — their answer type never changes
// (plan §2.1). Each setting carries when the business told Uplift its value, so the database can keep a newer
// change the owner made in Settings (`public.owner_copy_setup_settings`).

import type { SetupAnswers } from '$lib/setup/catalogue';
import type { SetupHelpAnswer } from '$lib/setup/help';
import { parseSetupHours, type SetupHours } from '$lib/setup/hours';
import { setupReuseSource } from '$lib/setup/reuse';

export type SetupSettingKey =
	| 'name'
	| 'trade'
	| 'phone'
	| 'address'
	| 'address_is_public'
	| 'timezone'
	| 'currency_code'
	| 'hours';

export type SetupSettingProposal = { value: unknown; told_at: string };
export type SetupSettingProposals = Partial<Record<SetupSettingKey, SetupSettingProposal>>;

/** How the last copy of one setting went. */
export type SetupSettingOutcome = 'copied' | 'same' | 'kept' | 'locked';

/** One setting's last copy, as the Setup tab shows it. */
export type SetupSettingCopy = {
	setting: SetupSettingKey;
	outcome: SetupSettingOutcome;
	checked_at: string;
};

/** Settings in the order the Setup tab lists them, with their names in words. */
export const SETUP_SETTING_LABELS: Record<SetupSettingKey, string> = {
	name: 'Business name',
	trade: 'Trade',
	phone: 'Public phone',
	address: 'Address',
	address_is_public: 'Address shown publicly',
	timezone: 'Time zone',
	currency_code: 'Currency',
	hours: 'Business hours'
};

/** One send, oldest first, as the copy reads it. */
export type SetupSendAnswers = { number: number; submitted_at: string; answers: SetupAnswers };

type Told = { value: string; told_at: string };

/** A client's own answer to `key` in one send, following a reused answer to its source. */
function givenValue(answers: SetupAnswers, key: string): string | null {
	const answer = answers[key];
	if (answer?.availability !== 'have') return null;
	const source = setupReuseSource(answer.value);
	if (source) return source === key ? null : givenValue(answers, source);
	const value = answer.value?.trim();
	return value ? value : null;
}

/**
 * The accepted value of one question and when the business told Uplift it: the client's own answer, from the
 * first send in the unbroken run of sends that held it, or Uplift's answer to their request for help.
 */
function told(
	sends: readonly SetupSendAnswers[],
	help: Readonly<Record<string, SetupHelpAnswer>>,
	key: string
): Told | null {
	const newest = sends.at(-1);
	if (!newest) return null;
	const value = givenValue(newest.answers, key);
	if (value === null) {
		const answer = newest.answers[key];
		const uplift = help[key]?.value?.trim();
		return answer?.availability === 'need_help' && uplift
			? { value: uplift, told_at: help[key].recorded_at }
			: null;
	}
	let first = newest;
	for (let index = sends.length - 2; index >= 0; index--) {
		if (givenValue(sends[index].answers, key) !== value) break;
		first = sends[index];
	}
	return { value, told_at: first.submitted_at };
}

const latest = (...times: string[]) =>
	times.reduce((a, b) => (new Date(a).getTime() >= new Date(b).getTime() ? a : b));

const minutes = (time: string) => Number(time.slice(0, 2)) * 60 + Number(time.slice(3, 5));

/**
 * Setup hours as the rows Business Hours keeps, Sunday first, or null when a day's periods overlap or run out of
 * order — Settings refuses those, so they are left for a person to sort out.
 */
export function businessHoursRows(hours: SetupHours) {
	if (hours.mode === 'appointment_only') return { mode: 'appointment_only' as const };
	const rows = [];
	for (const [weekday, day] of hours.days.entries()) {
		if (!day.open || day.all_day) {
			rows.push({
				weekday,
				period_index: 0,
				is_open: day.open,
				is_open_24h: day.open,
				opens_at: null,
				closes_at: null
			});
			continue;
		}
		let previousStart = -1;
		let previousEnd = -1;
		for (const [index, [opens, closes]] of day.periods.entries()) {
			const start = minutes(opens);
			const end = minutes(closes) <= start ? minutes(closes) + 1440 : minutes(closes);
			if (start <= previousStart || start < previousEnd) return null;
			previousStart = start;
			previousEnd = end;
			rows.push({
				weekday,
				period_index: index,
				is_open: true,
				is_open_24h: false,
				opens_at: opens,
				closes_at: closes
			});
		}
	}
	return { mode: 'weekly' as const, rows };
}

const ALWAYS_OPEN: SetupHours = {
	mode: 'weekly',
	days: Array.from({ length: 7 }, () => ({ open: true, all_day: true, periods: [] }))
};

/**
 * The settings a client's accepted answers fill. `acceptedKeys` are the questions of every section Uplift has
 * accepted on the newest send; `sends` every send, oldest first; `help` Uplift's answers to help requests.
 */
export function setupSettingProposals(input: {
	sends: readonly SetupSendAnswers[];
	acceptedKeys: ReadonlySet<string>;
	help: Readonly<Record<string, SetupHelpAnswer>>;
}): SetupSettingProposals {
	const read = (key: string) =>
		input.acceptedKeys.has(key) ? told(input.sends, input.help, key) : null;
	const proposals: SetupSettingProposals = {};

	const single: [SetupSettingKey, string][] = [
		['name', 'business.public_name'],
		['trade', 'business.trade'],
		['phone', 'business.public_phone'],
		['timezone', 'business.timezone'],
		['currency_code', 'business.currency']
	];
	for (const [setting, key] of single) {
		const answer = read(key);
		if (answer) proposals[setting] = { value: answer.value, told_at: answer.told_at };
	}

	const isPublic = read('business.address_public');
	if (isPublic && (isPublic.value === 'yes' || isPublic.value === 'no'))
		proposals.address_is_public = { value: isPublic.value === 'yes', told_at: isPublic.told_at };

	// An address is copied whole, and only with a street, a town and a country: half of one would mislead.
	const parts = {
		address_line1: read('business.address_line1'),
		address_line2: read('business.address_line2'),
		city: read('business.address_city'),
		region: read('business.address_region'),
		postal_code: read('business.address_postal_code'),
		country_code: read('business.country')
	};
	if (parts.address_line1 && parts.city && parts.country_code) {
		const given = Object.values(parts).filter((part): part is Told => part !== null);
		proposals.address = {
			value: Object.fromEntries(
				Object.entries(parts).map(([column, part]) => [column, part?.value ?? null])
			),
			told_at: latest(...given.map((part) => part.told_at))
		};
	}

	// "Open 24 hours" needs no weekly grid; otherwise the weekly hours answer is the hours.
	const availability = read('business.availability');
	const weekly = read('business.hours');
	let hours: { value: SetupHours; told_at: string } | null = null;
	if (availability?.value === 'always')
		hours = { value: ALWAYS_OPEN, told_at: availability.told_at };
	else if (availability?.value === 'appointment_only')
		hours = { value: { mode: 'appointment_only' }, told_at: availability.told_at };
	else if (weekly) {
		const parsed = parseSetupHours(weekly.value).value;
		if (parsed)
			hours = {
				value: parsed,
				told_at: availability ? latest(availability.told_at, weekly.told_at) : weekly.told_at
			};
	}
	const rows = hours ? businessHoursRows(hours.value) : null;
	if (hours && rows) proposals.hours = { value: rows, told_at: hours.told_at };

	return proposals;
}
