// Client onboarding B3b: the yes/no questions that decide whether a follow-up is asked — "Is your legal name
// different?" before the legal name — arrived after some clients had already answered the follow-up. Their
// answer is suggested from what they gave, so the follow-up and its old answer show again straight away, and the
// client confirms it like any other suggestion (blueprint global rule 1). Nothing is saved for them.

import type { SetupAnswers } from '$lib/setup/catalogue';

/** The organization's hours mode in Settings, as `organization_settings.hours_mode` keeps it. */
type HoursMode = string | null | undefined;

function given(answers: SetupAnswers, key: string): string | null {
	const answer = answers[key];
	return answer?.availability === 'have' ? answer.value?.trim() || null : null;
}

/** Suggested answers for the follow-up gates, from the client's earlier answers and the CRM's hours. */
export function followUpSuggestions(
	answers: SetupAnswers,
	hoursMode: HoursMode
): Record<string, string | null> {
	const legalName = given(answers, 'business.legal_name');
	const publicName = given(answers, 'business.public_name');
	const sameName = legalName && publicName && legalName.toLowerCase() === publicName.toLowerCase();

	return {
		'business.legal_name_differs': legalName ? (sameName ? 'no' : 'yes') : null,
		// The old question said "leave empty if the main contact approves", so only a named approver is evidence.
		'business.contact_is_approver': given(answers, 'business.approver_name') ? 'no' : null,
		'business.availability':
			given(answers, 'business.hours') || hoursMode === 'weekly'
				? 'set_hours'
				: hoursMode === 'appointment_only'
					? 'appointment_only'
					: null,
		'business.hours_seasonal_changes': given(answers, 'business.hours_seasonal') ? 'yes' : null
	};
}
