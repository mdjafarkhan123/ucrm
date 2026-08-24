// What the Settings cards are allowed to say. The rule is that a badge means a real gap a person can go
// and close, never decoration: Business Profile is incomplete only while something required is missing,
// and Business Hours is unset only until somebody chooses how the week works.
//
// Required means the smallest set the rest of the app cannot work honestly without: the name customers
// see, the timezone dates are read in, and the currency money is written in. Trade, phone, website,
// description, and the address are all optional.

export type BusinessProfileReadiness = {
	complete: boolean;
	missing: Array<'name' | 'timezone' | 'currency'>;
};

type ProfileFacts = {
	name: string | null;
	timezone_confirmed_at: string | null;
	currency_confirmed_at: string | null;
	currency_locked: boolean;
};

export function businessProfileReadiness(facts: ProfileFacts): BusinessProfileReadiness {
	const missing: BusinessProfileReadiness['missing'] = [];
	if (!facts.name || facts.name.trim().length < 2) missing.push('name');
	// A timezone and currency nobody confirmed are the signup defaults, not an answer.
	if (!facts.timezone_confirmed_at) missing.push('timezone');
	// Once a quote has gone out, the currency can never be changed or confirmed again through Save. It is
	// the organization's real, frozen answer either way, so a lock counts the same as a confirmation.
	if (!facts.currency_confirmed_at && !facts.currency_locked) missing.push('currency');

	return { complete: missing.length === 0, missing };
}

export function businessHoursIsSet(hoursMode: string) {
	return hoursMode !== 'not_configured';
}
