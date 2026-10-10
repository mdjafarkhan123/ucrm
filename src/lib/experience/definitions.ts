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
 * The experience the public Packages pages and the Application sell to (multi-industry foundation B2). The
 * Application does not ask which kind of business is applying yet; B3 replaces this with the buyer's answer.
 */
export const APPLICATION_EXPERIENCE: ExperienceKey = 'contractor';

export function isKnownExperience(key: string, version: number): key is ExperienceKey {
	if (!Object.hasOwn(KNOWN_EXPERIENCES, key)) return false;
	const versions: readonly number[] = KNOWN_EXPERIENCES[key as ExperienceKey].versions;
	return versions.includes(version);
}
