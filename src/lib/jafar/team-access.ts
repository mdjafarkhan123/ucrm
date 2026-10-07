/**
 * Which parts of the Jafar Panel each teammate role may use (ADR 0008). The front-door gate enforces it on
 * every request and the sidebar draws from it, so what a teammate is shown and what the server allows are
 * the same list. The platform owner passes everything; a path no area claims is the owner's alone.
 *
 * Starting access is Jafar's "careful start" (2026-10-07): each role can open its own areas, only Leads
 * and Support can change anything, and payment, provisioning, package changes, Team, and Settings stay
 * Jafar's until D2 adds per-teammate switches.
 */

export const TEAM_ROLES = ['sales', 'delivery', 'support', 'platform_operations'] as const;
export type TeamRole = (typeof TEAM_ROLES)[number];

export const TEAM_ROLE_LABELS: Record<TeamRole, string> = {
	sales: 'Sales',
	delivery: 'Delivery',
	support: 'Support',
	platform_operations: 'Platform Operations'
};

export type JafarArea =
	'leads' | 'applications' | 'onboarding' | 'support' | 'organizations' | 'packages' | 'operations';

/** `look` opens pages and reads; `work` also makes changes. */
export type AreaLevel = 'look' | 'work';

export const TEAM_ROLE_AREAS: Record<TeamRole, Partial<Record<JafarArea, AreaLevel>>> = {
	sales: { leads: 'work', applications: 'look' },
	delivery: { onboarding: 'look' },
	support: { support: 'work' },
	platform_operations: { organizations: 'look', packages: 'look', operations: 'look' }
};

/** What role, if any, limits the signed-in person. Null is the platform owner. */
export type JafarViewer = { role: TeamRole | null };

const AREA_PREFIXES: ReadonlyArray<readonly [JafarArea, readonly string[]]> = [
	['leads', ['/jafar/leads', '/api/jafar/leads']],
	['applications', ['/jafar/prospects', '/api/jafar/prospects']],
	['onboarding', ['/jafar/onboarding', '/api/jafar/onboarding']],
	['support', ['/jafar/support', '/api/jafar/support']],
	['organizations', ['/jafar/organizations', '/api/jafar/organizations']],
	[
		'packages',
		[
			'/jafar/packages',
			'/api/jafar/packages',
			'/api/jafar/package-offers',
			'/api/jafar/package-services'
		]
	],
	['operations', ['/jafar/operations', '/api/jafar/operations']]
];

/**
 * Changes inside a teammate's `work` area that still belong to Jafar. Matched on exact path and method.
 */
const OWNER_ONLY_ACTIONS: ReadonlyArray<{ path: string; methods: readonly string[] }> = [
	// Who Support replies appear from, for every contractor.
	{ path: '/api/jafar/support/settings', methods: ['PATCH'] }
];

const READ_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

function matchesPrefix(pathname: string, prefix: string) {
	return pathname === prefix || pathname.startsWith(`${prefix}/`);
}

export function areaForPath(pathname: string): JafarArea | null {
	for (const [area, prefixes] of AREA_PREFIXES) {
		if (prefixes.some((prefix) => matchesPrefix(pathname, prefix))) return area;
	}
	return null;
}

export function teamRoleAreas(role: TeamRole) {
	return TEAM_ROLE_AREAS[role];
}

/** Whether this person may make this request. The owner always may; an unmapped path is owner-only. */
export function canUseJafarPath(viewer: JafarViewer, pathname: string, method = 'GET') {
	if (viewer.role === null) return true;

	const area = areaForPath(pathname);
	if (!area) return false;

	const level = TEAM_ROLE_AREAS[viewer.role][area];
	if (!level) return false;

	const upperMethod = method.toUpperCase();
	if (READ_METHODS.has(upperMethod)) return true;
	if (level !== 'work') return false;

	return !OWNER_ONLY_ACTIONS.some(
		(action) => action.path === pathname && action.methods.includes(upperMethod)
	);
}

/** The page a teammate lands on when they open `/jafar` or a page outside their areas. */
export function teammateHomePath(role: TeamRole) {
	const firstArea = Object.keys(TEAM_ROLE_AREAS[role])[0] as JafarArea;
	const prefixes = AREA_PREFIXES.find(([area]) => area === firstArea)?.[1] ?? [];
	return prefixes.find((prefix) => prefix.startsWith('/jafar/')) ?? '/jafar/login';
}
