// Client onboarding A5g: an answer read back in words, for "You told us …" when a later question reuses it.
// Each kind is shown the way the client gave it: a choice by its words, a country by its name, hours day by day,
// a list row by row. A value that cannot be read shows as nothing rather than as code.

import { COUNTRIES } from '$lib/settings/countries';
import { setupListFieldFact, type SetupFact } from '$lib/setup/catalogue';
import { setupChoiceList } from '$lib/setup/answer-values';
import { parseSetupHours, parseSetupHoursExceptions } from '$lib/setup/hours';
import { setupListCellText, setupListRows } from '$lib/setup/lists';

const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const UNITS: Record<string, string> = {
	mi: 'miles',
	km: 'km',
	minutes: 'minutes',
	hours: 'hours',
	days: 'days'
};

function json(raw: string): unknown {
	try {
		return JSON.parse(raw);
	} catch {
		return undefined;
	}
}

function dateWords(value: string): string {
	const date = new Date(`${value}T00:00:00Z`);
	return Number.isNaN(date.getTime())
		? value
		: date.toLocaleDateString(undefined, { dateStyle: 'long', timeZone: 'UTC' });
}

function optionLabel(fact: SetupFact, value: string): string {
	return fact.options?.find((option) => option.value === value)?.label ?? value;
}

/** The answer as lines of words; most answers are one line. */
export function setupAnswerLines(fact: SetupFact, value: string): string[] {
	switch (fact.kind) {
		case 'choice':
		case 'choice_other':
			return [optionLabel(fact, value)];
		case 'multi_choice':
			return [(setupChoiceList(value) ?? []).map((item) => optionLabel(fact, item)).join(', ')];
		case 'country':
			return [COUNTRIES.find((country) => country.value === value)?.label ?? value];
		case 'date':
			return [dateWords(value)];
		case 'percentage':
			return [`${value}%`];
		case 'money': {
			const money = json(value) as { amount?: string; currency?: string } | undefined;
			if (!money?.amount || !money.currency) return [];
			try {
				return [
					new Intl.NumberFormat(undefined, { style: 'currency', currency: money.currency }).format(
						Number(money.amount)
					)
				];
			} catch {
				return [`${money.amount} ${money.currency}`];
			}
		}
		case 'distance':
		case 'duration': {
			const measure = json(value) as { amount?: number; unit?: string } | undefined;
			return measure?.amount
				? [`${measure.amount} ${UNITS[measure.unit ?? ''] ?? measure.unit}`]
				: [];
		}
		case 'colours':
			return [((json(value) as string[] | undefined) ?? []).join(', ')];
		case 'hours': {
			const hours = parseSetupHours(value).value;
			if (!hours) return [];
			if (hours.mode === 'appointment_only') return ['By appointment only'];
			return hours.days.map(
				(day, index) =>
					`${DAYS[index]}: ${
						!day.open
							? 'Closed'
							: day.all_day
								? 'Open 24 hours'
								: day.periods.map(([opens, closes]) => `${opens}–${closes}`).join(', ')
					}`
			);
		}
		case 'hours_exceptions':
			return (parseSetupHoursExceptions(value).value ?? []).map(
				(day) =>
					`${dateWords(day.date)}${day.name ? `, ${day.name}` : ''}: ${
						day.closed ? 'Closed' : `${day.opens}–${day.closes}`
					}`
			);
		case 'list':
			// Each row on one line, its filled boxes in order. A file box is left out: it reads as nothing.
			return setupListRows(value).flatMap((row) => {
				const cells = (fact.listFields ?? []).flatMap((field) => {
					const text = setupListCellText(row.values[field.key]);
					if (!text || field.kind === 'file') return [];
					return setupAnswerLines(setupListFieldFact(field), text);
				});
				return cells.length ? [cells.join(' · ')] : [];
			});
		default:
			return [value];
	}
}
