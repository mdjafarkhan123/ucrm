import type { ExperienceKey } from './definitions';

/**
 * Operational readiness (multi-industry foundation B8). Paying and finishing Setup open the Business
 * Workspace for private preparation. The real-world things a business does to its own customers each wait
 * for Uplift's sign-off on one *area*. The areas and the checks inside them are this registry's; the
 * database keeps Uplift's decisions (`organization_readiness_decisions`), one snapshot of an area's checks
 * per decision. An area with no decision is closed.
 */

export const READINESS_AREA_KEYS = [
	'public_intake',
	'customer_messaging',
	'customer_billing',
	'customer_automation'
] as const;

export type ReadinessAreaKey = (typeof READINESS_AREA_KEYS)[number];

export function isReadinessAreaKey(value: string): value is ReadinessAreaKey {
	return (READINESS_AREA_KEYS as readonly string[]).includes(value);
}

/** Who finishes a check: the business supplies a fact or approval, Uplift verifies or configures. */
export type ReadinessOwner = 'business' | 'uplift';

export type ReadinessCheckDefinition = {
	key: string;
	/** The remaining task, as the business reads it. */
	task: string;
	owner: ReadinessOwner;
};

export type ReadinessAreaDefinition = {
	key: ReadinessAreaKey;
	label: string;
	/** What the sign-off opens, finishing "Until Uplift signs this off, ...". */
	opens: string;
	/** What the business can keep doing meanwhile. */
	meanwhile: string;
	/** Areas that must be ready first. */
	requires: ReadinessAreaKey[];
	checks: ReadinessCheckDefinition[];
};

/**
 * Contractor's areas. The checks follow the go-live checks Uplift already runs for a client's website and
 * system (client onboarding and delivery plan, section 6) and Jobber's split between basic and advanced
 * account setup. Another experience brings its own list; a clinic's clinical checks never apply here.
 */
const CONTRACTOR_AREAS: ReadinessAreaDefinition[] = [
	{
		key: 'public_intake',
		label: 'Web requests and online booking',
		opens: 'new customers can send requests or book through your website',
		meanwhile: 'You can still add requests yourself and build your forms.',
		requires: [],
		checks: [
			{
				key: 'request_form_reviewed',
				task: 'Uplift checks that your request form reaches your CRM and reads well on a phone',
				owner: 'uplift'
			},
			{
				key: 'website_connected',
				task: 'Uplift connects your website address and secure connection',
				owner: 'uplift'
			},
			{
				key: 'services_confirmed',
				task: 'You confirm the services and areas your form offers',
				owner: 'business'
			}
		]
	},
	{
		key: 'customer_messaging',
		label: 'Email and texts to customers',
		opens: 'your team can email or text your customers from the CRM',
		meanwhile: 'You can still draft messages, save templates and read replies.',
		requires: [],
		checks: [
			{
				key: 'sender_email_verified',
				task: 'Uplift verifies the email address your messages are sent from',
				owner: 'uplift'
			},
			{
				key: 'text_number_registered',
				task: 'Uplift gets your text-message number approved',
				owner: 'uplift'
			},
			{
				key: 'contact_details_confirmed',
				task: 'You confirm your business name, phone and address for messages',
				owner: 'business'
			}
		]
	},
	{
		key: 'customer_billing',
		label: 'Quotes, invoices and payments',
		opens: 'quotes and invoices can be sent to your customers',
		meanwhile: 'You can still build quotes and invoices as drafts.',
		requires: [],
		checks: [
			{
				key: 'document_details_confirmed',
				task: 'You confirm the business details, tax details and terms shown on quotes and invoices',
				owner: 'business'
			},
			{
				key: 'documents_reviewed',
				task: 'Uplift checks how your quote and invoice emails and pages look',
				owner: 'uplift'
			},
			{
				key: 'payment_account_connected',
				task: 'You connect the account that receives online payments',
				owner: 'business'
			}
		]
	},
	{
		key: 'customer_automation',
		label: 'Automations and campaigns',
		opens: 'automations and marketing campaigns can start messaging your customers',
		meanwhile: 'You can still build and save automations and campaign drafts.',
		requires: ['customer_messaging'],
		checks: [
			{
				key: 'automations_reviewed',
				task: 'Uplift reviews your automations and campaign rules',
				owner: 'uplift'
			}
		]
	}
];

export const READINESS_CATALOG: Record<ExperienceKey, ReadinessAreaDefinition[]> = {
	contractor: CONTRACTOR_AREAS
};

/** The areas of an experience; an unknown experience has the Contractor list, the only one offered today. */
export function readinessAreasFor(experience: string | null | undefined) {
	return READINESS_CATALOG[(experience ?? 'contractor') as ExperienceKey] ?? CONTRACTOR_AREAS;
}

export type ReadinessCheckState = 'open' | 'done' | 'not_applicable';
export type ReadinessStatus = 'ready' | 'not_ready' | 'held';

export type ReadinessCheckEntry = { key: string; state: ReadinessCheckState; note?: string };

/** One decision as the pure rules need it. */
export type ReadinessDecisionFacts = {
	status: ReadinessStatus;
	source: 'review' | 'carried_over';
	checks: ReadinessCheckEntry[];
	business_message: string | null;
};

export type ReadinessTask = { key: string; task: string; owner: ReadinessOwner };

export type ReadinessAreaView = {
	key: ReadinessAreaKey;
	label: string;
	/** `not_started` means Uplift has not reviewed the area yet. */
	state: 'ready' | 'not_ready' | 'held' | 'not_started';
	/** True when the decision only carries an older business forward; nothing was reviewed. */
	carried_over: boolean;
	open: boolean;
	opens: string;
	meanwhile: string;
	tasks: ReadinessTask[];
	message: string | null;
	/** Areas that must be ready first and are not. */
	waiting_for: { key: ReadinessAreaKey; label: string }[];
};

/**
 * What the business sees for each area: the decision's state and, when the area is not open, the specific
 * tasks left with their owners. A check the decision does not mention counts as open, so a newly added
 * check never lets an older sign-off pass for it. A ready area stays closed while an area it requires is not
 * ready.
 */
export function describeReadiness(
	experience: string | null | undefined,
	decisions: Partial<Record<ReadinessAreaKey, ReadinessDecisionFacts | null>>
): ReadinessAreaView[] {
	const areas = readinessAreasFor(experience);
	const own = (area: ReadinessAreaDefinition): ReadinessAreaView => {
		const decision = decisions[area.key] ?? null;
		const states = new Map((decision?.checks ?? []).map((entry) => [entry.key, entry.state]));
		const openTasks: ReadinessTask[] = area.checks
			.filter((check) => (states.get(check.key) ?? 'open') === 'open')
			.map(({ key, task, owner }) => ({ key, task, owner }));
		const state = decision ? decision.status : 'not_started';
		return {
			key: area.key,
			label: area.label,
			state,
			carried_over: decision?.source === 'carried_over',
			open: state === 'ready',
			opens: area.opens,
			meanwhile: area.meanwhile,
			tasks: state === 'ready' ? [] : openTasks,
			message: decision?.business_message ?? null,
			waiting_for: []
		};
	};
	const views = areas.map(own);
	return views.map((view) => {
		const definition = areas.find((area) => area.key === view.key);
		const waitingFor = (definition?.requires ?? [])
			.map((key) => views.find((candidate) => candidate.key === key))
			.filter((required): required is ReadinessAreaView => Boolean(required) && !required?.open)
			.map((required) => ({ key: required.key, label: required.label }));
		return { ...view, open: view.open && waitingFor.length === 0, waiting_for: waitingFor };
	});
}

/** The refusal a business reads when it tries a real-world action in an area that is not open. */
export function readinessRefusal(view: ReadinessAreaView): string {
	if (view.state === 'held') {
		return `${view.label}: Uplift has put this on hold. ${view.message ?? 'Contact Uplift Support.'} ${view.meanwhile}`;
	}
	const parts: string[] = [];
	if (view.waiting_for.length > 0) {
		parts.push(
			`First, ${view.waiting_for.map((area) => area.label).join(' and ')} must be signed off.`
		);
	}
	if (view.state === 'not_started') {
		parts.push('Uplift has not reviewed this yet.');
	} else if (view.tasks.length > 0) {
		parts.push(
			`Still to do: ${view.tasks
				.map((task) => `${task.task} (${task.owner === 'business' ? 'you' : 'Uplift'})`)
				.join('; ')}.`
		);
	} else if (view.waiting_for.length === 0) {
		parts.push('Uplift is doing its final review.');
	}
	return `${view.label} are not open yet. ${parts.join(' ')} ${view.meanwhile}`
		.replace(/\s+/g, ' ')
		.trim();
}
