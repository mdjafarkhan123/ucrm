// What the contractor's app knows about its own access, from `public.contractor_account_standing`.
// Only owners and admins are told about a coming pause or that a pause is about payment (package plan,
// Jafar 2026-09-30); everyone else only learns that access is paused.
export type AccountStanding =
	| { state: 'active'; organization_name: string; can_manage: boolean }
	| {
			state: 'grace';
			organization_name: string;
			can_manage: true;
			covered_through: string;
			/** The last local calendar day of full access, `YYYY-MM-DD`. */
			last_access_day: string;
	  }
	| {
			state: 'paused';
			organization_name: string;
			can_manage: boolean;
			/** Null for staff, who are not told why. */
			reason: 'payment' | 'other' | null;
	  };

export const PLATFORM_CONTACT_EMAIL = 'hello@upliftcontractor.com';

// A calendar day, not a moment: formatted in UTC so it never shifts a day in the viewer's time zone.
export function formatCalendarDay(day: string) {
	return new Intl.DateTimeFormat(undefined, {
		weekday: 'long',
		day: 'numeric',
		month: 'long',
		timeZone: 'UTC'
	}).format(new Date(`${day}T00:00:00Z`));
}
