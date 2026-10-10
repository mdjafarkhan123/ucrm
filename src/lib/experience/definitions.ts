/**
 * The Industry experiences this build of the app knows how to run (multi-industry foundation B1). The
 * database holds each experience's reviewable, versioned definition; this registry is the code's half of
 * the handshake. A profile naming an experience or version the code does not know resolves to no
 * experience at all, never to the closest-looking one.
 */
export const KNOWN_EXPERIENCES = {
	contractor: { name: 'Contractor', versions: [1] }
} as const satisfies Record<string, { name: string; versions: readonly number[] }>;

export type ExperienceKey = keyof typeof KNOWN_EXPERIENCES;

/**
 * The experience the public Packages pages and the sales team's "Pricing shared" list sell to. The
 * Application asks each buyer which kind of business it is (B3); these pages still speak to Contractors
 * until another experience is offered.
 */
export const PRICING_PAGE_EXPERIENCE: ExperienceKey = 'contractor';

/**
 * The Application's answers for a business that fits no listed Business type (multi-industry foundation
 * B3). Neither chooses a package: Uplift reviews the business and recommends one, and "medspa" only records
 * interest until Medspa & Clinical Wellness is offered.
 */
export const APPLICATION_OTHER_CHOICES = {
	medspa: {
		label: 'Medspa or clinic',
		hint: 'Coming soon. Tell us about your clinic and we will be in touch.'
	},
	something_else: {
		label: 'Something else or not sure',
		hint: 'Tell us about your work and Uplift will recommend the right package.'
	}
} as const;

export type ApplicationOtherChoice = keyof typeof APPLICATION_OTHER_CHOICES;

export function isKnownExperience(key: string, version: number): key is ExperienceKey {
	if (!Object.hasOwn(KNOWN_EXPERIENCES, key)) return false;
	const versions: readonly number[] = KNOWN_EXPERIENCES[key as ExperienceKey].versions;
	return versions.includes(version);
}
