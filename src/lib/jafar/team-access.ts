/**
 * Which parts of the Jafar Panel each teammate may use (ADR 0008). The front-door gate enforces it on every
 * request and the sidebar draws from it, so what a teammate is shown and what the server allows are the
 * same list. The platform owner passes everything; a path no area claims is the owner's alone.
 *
 * A teammate's access is their role's starting set with Jafar's individual adjustments on top (D2): each
 * area set to off, look, or work, and sensitive actions granted one by one. Every role starts with no
 * sensitive actions. Managing the team, Settings, and anything behind the owner's password step-up stay
 * Jafar's whatever is granted.
 */

export const TEAM_ROLES = ['sales', 'delivery', 'support', 'platform_operations'] as const;
export type TeamRole = (typeof TEAM_ROLES)[number];

export const TEAM_ROLE_LABELS: Record<TeamRole, string> = {
	sales: 'Sales',
	delivery: 'Delivery',
	support: 'Support',
	platform_operations: 'Platform Operations'
};

export const JAFAR_AREAS = [
	'leads',
	'applications',
	'onboarding',
	'support',
	'organizations',
	'packages',
	'operations'
] as const;
export type JafarArea = (typeof JAFAR_AREAS)[number];

export const JAFAR_AREA_LABELS: Record<JafarArea, string> = {
	leads: 'Leads',
	applications: 'Applications',
	onboarding: 'Onboarding',
	support: 'Support inbox',
	organizations: 'Organizations',
	packages: 'Packages',
	operations: 'Operations'
};

/** `look` opens pages and reads; `work` also makes changes. */
export type AreaLevel = 'look' | 'work';
/** What Jafar can choose for one area: off, or one of the levels. */
export type AreaSetting = 'none' | AreaLevel;

/**
 * The highest level an area offers. Every change in Packages is the "Change packages & prices" action, so
 * the area itself only opens for looking.
 */
export const AREA_MAX_LEVEL: Record<JafarArea, AreaLevel> = {
	leads: 'work',
	applications: 'work',
	onboarding: 'work',
	support: 'work',
	organizations: 'work',
	packages: 'look',
	operations: 'work'
};

export const TEAM_ROLE_AREAS: Record<TeamRole, Partial<Record<JafarArea, AreaLevel>>> = {
	sales: { leads: 'work', applications: 'look' },
	delivery: { onboarding: 'look' },
	support: { support: 'work' },
	platform_operations: { organizations: 'look', packages: 'look', operations: 'look' }
};

export const SENSITIVE_ACTIONS = ['payments', 'client_setup', 'packages', 'client_accounts'] as const;
export type SensitiveAction = (typeof SENSITIVE_ACTIONS)[number];

/** Each sensitive action lives in one area, which must be open for the action to be granted. */
export const SENSITIVE_ACTION_DETAILS: Record<
	SensitiveAction,
	{ label: string; description: string; area: JafarArea }
> = {
	payments: {
		label: 'Confirm and undo payments',
		description: 'Confirm an Application was paid, reverse a payment, or correct its package.',
		area: 'applications'
	},
	client_setup: {
		label: 'Set up client accounts',
		description: 'Create the client’s account from a paid Application and send their setup email.',
		area: 'applications'
	},
	packages: {
		label: 'Change packages and prices',
		description: 'Edit, publish, and remove packages, offers, and services on the pricing page.',
		area: 'packages'
	},
	client_accounts: {
		label: 'Client account controls',
		description:
			'Inside a client’s organization: Stripe, email and text sending, automation and chat permission, exceptions, and their team.',
		area: 'organizations'
	}
};

/** The access a teammate actually has: open areas with their level, and granted sensitive actions. */
export type TeamAccess = {
	areas: Partial<Record<JafarArea, AreaLevel>>;
	actions: SensitiveAction[];
};

/** What Jafar set differently from the role: stored on the teammate's record. */
export type TeamAccessAdjustments = {
	areas: Partial<Record<JafarArea, AreaSetting>>;
	actions: SensitiveAction[];
};

/** Who is signed in. Null role is the platform owner; a teammate without `access` gets their role's. */
export type JafarViewer = { role: TeamRole | null; access?: TeamAccess | null };

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
 * A path pattern: `*` stands for one segment (a record id). `subtree` also matches everything below it.
 */
type PathRule = { pattern: string; subtree?: boolean };

/** Changes that need a sensitive action, whatever the area's level. */
const SENSITIVE_ACTION_PATHS: Record<SensitiveAction, readonly PathRule[]> = {
	payments: [
		{ pattern: '/api/jafar/prospects/*/confirm-payment' },
		{ pattern: '/api/jafar/prospects/*/reverse-payment' },
		{ pattern: '/api/jafar/prospects/*/correct-package' }
	],
	client_setup: [
		{ pattern: '/api/jafar/prospects/*/provision' },
		{ pattern: '/api/jafar/prospects/*/send-setup-email' }
	],
	packages: [
		{ pattern: '/api/jafar/packages', subtree: true },
		{ pattern: '/api/jafar/package-offers', subtree: true },
		{ pattern: '/api/jafar/package-services', subtree: true }
	],
	client_accounts: [
		{ pattern: '/api/jafar/organizations/*/automation', subtree: true },
		{ pattern: '/api/jafar/organizations/*/communications', subtree: true },
		{ pattern: '/api/jafar/organizations/*/exceptions', subtree: true },
		{ pattern: '/api/jafar/organizations/*/payments', subtree: true },
		{ pattern: '/api/jafar/organizations/*/team', subtree: true }
	]
};

/**
 * Changes that stay Jafar's even inside a teammate's area or action: those behind the owner's password
 * step-up (money, closing an account, recovering a client's administrator) and platform-wide settings.
 */
const OWNER_ONLY_CHANGES: readonly PathRule[] = [
	// Who Support replies appear from, for every contractor.
	{ pattern: '/api/jafar/support/settings' },
	{ pattern: '/api/jafar/organizations/*/billing', subtree: true },
	{ pattern: '/api/jafar/organizations/*/closure', subtree: true },
	{ pattern: '/api/jafar/organizations/*/lifecycle', subtree: true },
	{ pattern: '/api/jafar/organizations/*/team/*/administrator-recovery', subtree: true },
	{ pattern: '/api/jafar/organizations/*/communications/sms/adjustments', subtree: true },
	{ pattern: '/api/jafar/organizations/*/communications/sms/credit-topups', subtree: true },
	{ pattern: '/api/jafar/organizations/*/communications/sms/holds', subtree: true },
	{ pattern: '/api/jafar/organizations/*/communications/sms/promotional-credits', subtree: true },
	{ pattern: '/api/jafar/organizations/*/communications/sms/refunds', subtree: true }
];

const READ_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

function matchesPrefix(pathname: string, prefix: string) {
	return pathname === prefix || pathname.startsWith(`${prefix}/`);
}

function matchesRule(pathname: string, rule: PathRule) {
	const path = pathname.split('/');
	const pattern = rule.pattern.split('/');
	if (path.length < pattern.length || (!rule.subtree && path.length !== pattern.length)) return false;
	return pattern.every((segment, index) => segment === '*' || segment === path[index]);
}

export function areaForPath(pathname: string): JafarArea | null {
	for (const [area, prefixes] of AREA_PREFIXES) {
		if (prefixes.some((prefix) => matchesPrefix(pathname, prefix))) return area;
	}
	return null;
}

export function sensitiveActionForPath(pathname: string): SensitiveAction | null {
	for (const action of SENSITIVE_ACTIONS) {
		if (SENSITIVE_ACTION_PATHS[action].some((rule) => matchesRule(pathname, rule))) return action;
	}
	return null;
}

export function isOwnerOnlyChange(pathname: string) {
	return OWNER_ONLY_CHANGES.some((rule) => matchesRule(pathname, rule));
}

/** The role's starting access, before any individual adjustment. */
export function roleAccess(role: TeamRole): TeamAccess {
	return { areas: { ...TEAM_ROLE_AREAS[role] }, actions: [] };
}

/** The role's access with Jafar's adjustments applied, ignoring anything the rules would not allow. */
export function effectiveTeamAccess(
	role: TeamRole,
	adjustments: TeamAccessAdjustments | null | undefined
): TeamAccess {
	const areas: TeamAccess['areas'] = {};
	for (const area of JAFAR_AREAS) {
		const setting = adjustments?.areas[area] ?? TEAM_ROLE_AREAS[role][area] ?? 'none';
		if (setting === 'none') continue;
		areas[area] = setting === 'work' && AREA_MAX_LEVEL[area] === 'look' ? 'look' : setting;
	}
	const actions = SENSITIVE_ACTIONS.filter(
		(action) =>
			adjustments?.actions.includes(action) && areas[SENSITIVE_ACTION_DETAILS[action].area]
	);
	return { areas, actions };
}

/** What to store so that `effectiveTeamAccess(role, …)` gives back `access`: only what differs. */
export function adjustmentsFor(role: TeamRole, access: TeamAccess): TeamAccessAdjustments {
	const areas: TeamAccessAdjustments['areas'] = {};
	for (const area of JAFAR_AREAS) {
		const wanted = access.areas[area] ?? 'none';
		const standard = TEAM_ROLE_AREAS[role][area] ?? 'none';
		if (wanted !== standard) areas[area] = wanted;
	}
	return { areas, actions: SENSITIVE_ACTIONS.filter((action) => access.actions.includes(action)) };
}

/** Why this access cannot be saved, in words for Jafar, or null when it can. */
export function teamAccessProblem(access: TeamAccess): string | null {
	const open = JAFAR_AREAS.filter((area) => access.areas[area]);
	if (open.length === 0) {
		return 'A teammate needs at least one area. To take away all access, remove them from the team.';
	}
	for (const area of open) {
		if (access.areas[area] === 'work' && AREA_MAX_LEVEL[area] === 'look') {
			return `${JAFAR_AREA_LABELS[area]} can only be opened to look. Changes there are a separate permission.`;
		}
	}
	for (const action of access.actions) {
		const { area, label } = SENSITIVE_ACTION_DETAILS[action];
		if (!access.areas[area]) return `“${label}” needs ${JAFAR_AREA_LABELS[area]} to be open.`;
	}
	return null;
}

/** Reads the adjustments stored on a teammate's record, dropping anything this version does not know. */
export function storedTeamAccessAdjustments(
	areaAdjustments: unknown,
	actionGrants: readonly string[] | null | undefined
): TeamAccessAdjustments {
	const areas: TeamAccessAdjustments['areas'] = {};
	if (areaAdjustments && typeof areaAdjustments === 'object' && !Array.isArray(areaAdjustments)) {
		for (const area of JAFAR_AREAS) {
			const setting = (areaAdjustments as Record<string, unknown>)[area];
			if (setting === 'none' || setting === 'look' || setting === 'work') areas[area] = setting;
		}
	}
	const actions = SENSITIVE_ACTIONS.filter((action) => actionGrants?.includes(action));
	return { areas, actions };
}

function viewerAccess(viewer: JafarViewer & { role: TeamRole }) {
	return viewer.access ?? roleAccess(viewer.role);
}

/** Whether this person may make this request. The owner always may; an unmapped path is owner-only. */
export function canUseJafarPath(viewer: JafarViewer, pathname: string, method = 'GET') {
	if (viewer.role === null) return true;

	const area = areaForPath(pathname);
	if (!area) return false;

	const access = viewerAccess(viewer as JafarViewer & { role: TeamRole });
	const level = access.areas[area];
	if (!level) return false;

	if (READ_METHODS.has(method.toUpperCase())) return true;
	if (isOwnerOnlyChange(pathname)) return false;

	const action = sensitiveActionForPath(pathname);
	if (action) return access.actions.includes(action);
	return level === 'work';
}

/** The page a teammate lands on when they open `/jafar` or a page outside their areas. */
export function teammateHomePath(viewer: JafarViewer & { role: TeamRole }) {
	const access = viewerAccess(viewer);
	const firstArea = JAFAR_AREAS.find((area) => access.areas[area]);
	const prefixes = AREA_PREFIXES.find(([area]) => area === firstArea)?.[1] ?? [];
	return prefixes.find((prefix) => prefix.startsWith('/jafar/')) ?? '/jafar/login';
}
