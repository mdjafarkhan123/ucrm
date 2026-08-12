export type OrganizationDetailScenario =
	| 'active'
	| 'overdue'
	| 'setup-pending'
	| 'suspended'
	| 'feature-exception'
	| 'carrier-rejection'
	| 'provider-outage'
	| 'failed-work';

export type PreviewTone = 'success' | 'warning' | 'critical' | 'informative' | 'inactive';

type Integration = {
	name: string;
	state: string;
	tone: PreviewTone;
	detail: string;
	nextAction: string;
};

type HistoryItem = {
	at: string;
	title: string;
	detail: string;
	tone: PreviewTone;
};

export type OrganizationDetailPreview = {
	id: string;
	scenario: OrganizationDetailScenario;
	name: string;
	slug: string;
	lifecycle: string;
	lifecycleTone: PreviewTone;
	setup: { state: string; tone: PreviewTone; detail: string };
	warning: { title: string; detail: string; tone: PreviewTone } | null;
	commercial: {
		packageName: string;
		packageVersion: string;
		paidThrough: string;
		grace: string;
		freeAccess: string;
		exception: string;
	};
	integrations: Integration[];
	team: { name: string; role: string; access: string; note: string }[];
	history: HistoryItem[];
	recovery: { state: string; tone: PreviewTone; detail: string };
};

const team = [
	{
		name: 'Maya Patel',
		role: 'Owner',
		access: 'Full organization access',
		note: 'Primary administrator'
	},
	{
		name: 'Jordan Bell',
		role: 'Dispatcher',
		access: 'Schedule and client access',
		note: 'Last active today'
	},
	{
		name: 'Avery Chen',
		role: 'Technician',
		access: 'Assigned jobs only',
		note: 'No access warning'
	}
];

const identity: Record<OrganizationDetailScenario, { id: string; name: string; slug: string }> = {
	active: {
		id: 'northstar-heating-air',
		name: 'Northstar Heating & Air',
		slug: 'northstar-heating-air'
	},
	overdue: { id: 'ridgeway-electric', name: 'Ridgeway Electric', slug: 'ridgeway-electric' },
	'setup-pending': {
		id: 'cedar-hill-plumbing',
		name: 'Cedar Hill Plumbing',
		slug: 'cedar-hill-plumbing'
	},
	suspended: { id: 'harborline-hvac', name: 'Harborline HVAC', slug: 'harborline-hvac' },
	'feature-exception': {
		id: 'evergreen-property-care',
		name: 'Evergreen Property Care',
		slug: 'evergreen-property-care'
	},
	'carrier-rejection': {
		id: 'brightline-electric',
		name: 'Brightline Electric',
		slug: 'brightline-electric'
	},
	'provider-outage': {
		id: 'maple-street-services',
		name: 'Maple Street Services',
		slug: 'maple-street-services'
	},
	'failed-work': {
		id: 'westfield-garden-care',
		name: 'Westfield Garden Care',
		slug: 'westfield-garden-care'
	}
};

function base(scenario: OrganizationDetailScenario) {
	return { ...identity[scenario], team };
}

const scenarios: Record<OrganizationDetailScenario, OrganizationDetailPreview> = {
	active: {
		...base('active'),
		scenario: 'active',
		lifecycle: 'Active',
		lifecycleTone: 'success',
		setup: {
			state: 'Administrator ready',
			tone: 'success',
			detail: 'Maya completed password setup.'
		},
		warning: null,
		commercial: {
			packageName: 'Growth',
			packageVersion: 'Growth · v3',
			paidThrough: 'September 30, 2026',
			grace: 'Not in grace',
			freeAccess: 'Paid access',
			exception: 'No active exceptions'
		},
		integrations: [
			{
				name: 'SMS and phone',
				state: 'Ready',
				tone: 'success',
				detail: 'Assigned number and credits are healthy.',
				nextAction: 'No action needed'
			},
			{
				name: 'Email',
				state: 'Fallback ready',
				tone: 'informative',
				detail: 'Using the verified platform sending domain.',
				nextAction: 'Contractor can add a domain'
			},
			{
				name: 'Payments',
				state: 'Contractor setup needed',
				tone: 'warning',
				detail: 'No payment-provider account is connected.',
				nextAction: 'Contractor action required'
			},
			{
				name: 'Webchat',
				state: 'Not enabled',
				tone: 'inactive',
				detail: 'Package eligibility is available.',
				nextAction: 'Contractor can enable it'
			}
		],
		history: [
			{
				at: 'Today · 10:24',
				title: 'Access checked',
				detail: 'All commercial gates resolved as available.',
				tone: 'success'
			},
			{
				at: 'Aug 7 · 15:02',
				title: 'Package activated',
				detail: 'Growth v3 applied after payment confirmation.',
				tone: 'informative'
			},
			{
				at: 'Aug 7 · 14:58',
				title: 'Organization provisioned',
				detail: 'Initial owner membership created.',
				tone: 'success'
			}
		],
		recovery: {
			state: 'No recovery work',
			tone: 'success',
			detail: 'No failed background work is waiting for review.'
		}
	},
	overdue: {
		...base('overdue'),
		scenario: 'overdue',
		lifecycle: 'Active',
		lifecycleTone: 'success',
		setup: {
			state: 'Administrator ready',
			tone: 'success',
			detail: 'Maya completed password setup.'
		},
		warning: {
			title: 'Paid-through date has passed',
			detail: 'Record a renewal or correction before confirming any lifecycle change.',
			tone: 'warning'
		},
		commercial: {
			packageName: 'Growth',
			packageVersion: 'Growth · v3',
			paidThrough: 'August 3, 2026',
			grace: 'Grace ended August 10, 2026',
			freeAccess: 'Paid access',
			exception: 'No active exceptions'
		},
		integrations: [
			{
				name: 'SMS and phone',
				state: 'Ready',
				tone: 'success',
				detail: 'Assigned number and credits are healthy.',
				nextAction: 'No action needed'
			},
			{
				name: 'Email',
				state: 'Fallback ready',
				tone: 'informative',
				detail: 'Using the verified platform sending domain.',
				nextAction: 'Contractor can add a domain'
			},
			{
				name: 'Payments',
				state: 'Contractor setup needed',
				tone: 'warning',
				detail: 'No payment-provider account is connected.',
				nextAction: 'Contractor action required'
			},
			{
				name: 'Webchat',
				state: 'Not enabled',
				tone: 'inactive',
				detail: 'Package eligibility is available.',
				nextAction: 'Contractor can enable it'
			}
		],
		history: [
			{
				at: 'Today · 09:10',
				title: 'Commercial review due',
				detail: 'Manual owner review is required after grace.',
				tone: 'warning'
			},
			{
				at: 'Aug 3 · 12:20',
				title: 'Paid-through date reached',
				detail: 'Automatic suspension is intentionally disabled.',
				tone: 'informative'
			}
		],
		recovery: {
			state: 'No recovery work',
			tone: 'success',
			detail: 'No failed background work is waiting for review.'
		}
	},
	'setup-pending': {
		...base('setup-pending'),
		scenario: 'setup-pending',
		lifecycle: 'Active',
		lifecycleTone: 'success',
		setup: {
			state: 'Password setup pending',
			tone: 'warning',
			detail: 'The setup email was issued 18 hours ago and has not been completed.'
		},
		warning: {
			title: 'Administrator setup is unfinished',
			detail: 'The organization remains active. A safe resend will be connected in a later phase.',
			tone: 'warning'
		},
		commercial: {
			packageName: 'Growth',
			packageVersion: 'Growth · v3',
			paidThrough: 'September 30, 2026',
			grace: 'Not in grace',
			freeAccess: 'Paid access',
			exception: 'No active exceptions'
		},
		integrations: [
			{
				name: 'SMS and phone',
				state: 'Awaiting administrator',
				tone: 'inactive',
				detail: 'No contractor setup is available yet.',
				nextAction: 'Wait for password setup'
			},
			{
				name: 'Email',
				state: 'Fallback ready',
				tone: 'informative',
				detail: 'Transactional fallback is available.',
				nextAction: 'No action needed'
			},
			{
				name: 'Payments',
				state: 'Not configured',
				tone: 'inactive',
				detail: 'The contractor has not connected an account.',
				nextAction: 'Contractor action required'
			},
			{
				name: 'Webchat',
				state: 'Not enabled',
				tone: 'inactive',
				detail: 'Package eligibility is available.',
				nextAction: 'Contractor can enable it'
			}
		],
		history: [
			{
				at: 'Today · 08:42',
				title: 'Password setup remains pending',
				detail: 'Delivery was accepted by the provider; no password is visible to Jafar.',
				tone: 'warning'
			},
			{
				at: 'Yesterday · 14:10',
				title: 'Setup email issued',
				detail: 'Single-use email link created for the intended recipient.',
				tone: 'informative'
			}
		],
		recovery: {
			state: 'No recovery work',
			tone: 'success',
			detail: 'No failed background work is waiting for review.'
		}
	},
	suspended: {
		...base('suspended'),
		scenario: 'suspended',
		lifecycle: 'Suspended',
		lifecycleTone: 'critical',
		setup: {
			state: 'Administrator ready',
			tone: 'success',
			detail: 'Maya completed password setup before suspension.'
		},
		warning: {
			title: 'Contractor access is blocked',
			detail: 'Existing invoices remain view-only and payment reconciliation can continue.',
			tone: 'critical'
		},
		commercial: {
			packageName: 'Growth',
			packageVersion: 'Growth · v3',
			paidThrough: 'July 31, 2026',
			grace: 'Grace ended August 7, 2026',
			freeAccess: 'Paid access',
			exception: 'No active exceptions'
		},
		integrations: [
			{
				name: 'SMS and phone',
				state: 'Outbound paused',
				tone: 'critical',
				detail: 'Necessary inbound events remain available.',
				nextAction: 'Review before reactivation'
			},
			{
				name: 'Email',
				state: 'Outbound paused',
				tone: 'critical',
				detail: 'Receipts and security events may continue.',
				nextAction: 'Review before reactivation'
			},
			{
				name: 'Payments',
				state: 'Reconciliation allowed',
				tone: 'informative',
				detail: 'Existing valid invoice payments can continue.',
				nextAction: 'No action needed'
			},
			{
				name: 'Webchat',
				state: 'Public actions paused',
				tone: 'critical',
				detail: 'New requests and chat initiation are unavailable.',
				nextAction: 'Review before reactivation'
			}
		],
		history: [
			{
				at: 'Aug 10 · 11:40',
				title: 'Organization suspended',
				detail: 'Reason recorded privately after identity reconfirmation.',
				tone: 'critical'
			},
			{
				at: 'Aug 10 · 11:38',
				title: 'Commercial eligibility reviewed',
				detail: 'Late renewal was not recorded.',
				tone: 'warning'
			}
		],
		recovery: {
			state: 'Relevance review needed',
			tone: 'warning',
			detail: 'Paused outbound work must be reviewed before anything resumes.'
		}
	},
	'feature-exception': {
		...base('feature-exception'),
		scenario: 'feature-exception',
		lifecycle: 'Active',
		lifecycleTone: 'success',
		setup: {
			state: 'Administrator ready',
			tone: 'success',
			detail: 'Maya completed password setup.'
		},
		warning: {
			title: 'Temporary feature exception',
			detail: 'Webchat is enabled through September 1, 2026; the package definition is unchanged.',
			tone: 'informative'
		},
		commercial: {
			packageName: 'Starter',
			packageVersion: 'Starter · v2',
			paidThrough: 'September 30, 2026',
			grace: 'Not in grace',
			freeAccess: 'Paid access',
			exception: 'Webchat enabled until September 1, 2026'
		},
		integrations: [
			{
				name: 'SMS and phone',
				state: 'Ready',
				tone: 'success',
				detail: 'Assigned number and credits are healthy.',
				nextAction: 'No action needed'
			},
			{
				name: 'Email',
				state: 'Fallback ready',
				tone: 'informative',
				detail: 'Using the verified platform sending domain.',
				nextAction: 'Contractor can add a domain'
			},
			{
				name: 'Payments',
				state: 'Not included',
				tone: 'inactive',
				detail: 'The current package does not include platform payment eligibility.',
				nextAction: 'Package review needed'
			},
			{
				name: 'Webchat',
				state: 'Enabled by exception',
				tone: 'informative',
				detail: 'Contractor preference is enabled.',
				nextAction: 'Review before expiry'
			}
		],
		history: [
			{
				at: 'Aug 11 · 10:00',
				title: 'Feature exception granted',
				detail: 'Webchat exception has a recorded reason and expiry.',
				tone: 'informative'
			},
			{
				at: 'Aug 7 · 15:02',
				title: 'Package activated',
				detail: 'Starter v2 remains the commercial baseline.',
				tone: 'success'
			}
		],
		recovery: {
			state: 'No recovery work',
			tone: 'success',
			detail: 'No failed background work is waiting for review.'
		}
	},
	'carrier-rejection': {
		...base('carrier-rejection'),
		scenario: 'carrier-rejection',
		lifecycle: 'Active',
		lifecycleTone: 'success',
		setup: {
			state: 'Administrator ready',
			tone: 'success',
			detail: 'Maya completed password setup.'
		},
		warning: {
			title: 'Carrier registration was rejected',
			detail:
				'The contractor needs to resubmit attested consent information before SMS sending can start.',
			tone: 'warning'
		},
		commercial: {
			packageName: 'Growth',
			packageVersion: 'Growth · v3',
			paidThrough: 'September 30, 2026',
			grace: 'Not in grace',
			freeAccess: 'Paid access',
			exception: 'No active exceptions'
		},
		integrations: [
			{
				name: 'SMS and phone',
				state: 'Carrier resubmission needed',
				tone: 'warning',
				detail: 'Number stays assigned; outbound SMS is unavailable.',
				nextAction: 'Contractor attestation required'
			},
			{
				name: 'Email',
				state: 'Fallback ready',
				tone: 'informative',
				detail: 'Using the verified platform sending domain.',
				nextAction: 'No action needed'
			},
			{
				name: 'Payments',
				state: 'Contractor setup needed',
				tone: 'warning',
				detail: 'No payment-provider account is connected.',
				nextAction: 'Contractor action required'
			},
			{
				name: 'Webchat',
				state: 'Not enabled',
				tone: 'inactive',
				detail: 'Package eligibility is available.',
				nextAction: 'Contractor can enable it'
			}
		],
		history: [
			{
				at: 'Today · 08:04',
				title: 'Carrier registration rejected',
				detail: 'Provider response is sanitized; raw provider evidence is private.',
				tone: 'warning'
			},
			{
				at: 'Aug 8 · 16:31',
				title: 'Registration submitted',
				detail: 'Contractor attested legal business information.',
				tone: 'informative'
			}
		],
		recovery: {
			state: 'Owner review due',
			tone: 'warning',
			detail: 'Check the provider response and request a corrected contractor attestation.'
		}
	},
	'provider-outage': {
		...base('provider-outage'),
		scenario: 'provider-outage',
		lifecycle: 'Active',
		lifecycleTone: 'success',
		setup: {
			state: 'Administrator ready',
			tone: 'success',
			detail: 'Maya completed password setup.'
		},
		warning: {
			title: 'SMS provider health incident',
			detail: 'Configured state is preserved, but effective SMS access is temporarily unavailable.',
			tone: 'critical'
		},
		commercial: {
			packageName: 'Growth',
			packageVersion: 'Growth · v3',
			paidThrough: 'September 30, 2026',
			grace: 'Not in grace',
			freeAccess: 'Paid access',
			exception: 'No active exceptions'
		},
		integrations: [
			{
				name: 'SMS and phone',
				state: 'Provider outage',
				tone: 'critical',
				detail: 'Last provider check failed 7 minutes ago.',
				nextAction: 'Platform team action required'
			},
			{
				name: 'Email',
				state: 'Fallback ready',
				tone: 'informative',
				detail: 'Using the verified platform sending domain.',
				nextAction: 'No action needed'
			},
			{
				name: 'Payments',
				state: 'Ready',
				tone: 'success',
				detail: 'Account readiness was last checked today.',
				nextAction: 'No action needed'
			},
			{
				name: 'Webchat',
				state: 'Ready',
				tone: 'success',
				detail: 'Public widget is healthy.',
				nextAction: 'No action needed'
			}
		],
		history: [
			{
				at: 'Today · 10:17',
				title: 'Provider health check failed',
				detail: 'Outbound SMS was paused without changing contractor preferences.',
				tone: 'critical'
			},
			{
				at: 'Today · 10:10',
				title: 'Provider health check succeeded',
				detail: 'Last known ready state retained for diagnosis.',
				tone: 'informative'
			}
		],
		recovery: {
			state: 'Retrying',
			tone: 'critical',
			detail: 'Retry 2 of 5 is scheduled for 10:32. The retry identity prevents duplicate sends.'
		}
	},
	'failed-work': {
		...base('failed-work'),
		scenario: 'failed-work',
		lifecycle: 'Active',
		lifecycleTone: 'success',
		setup: {
			state: 'Administrator ready',
			tone: 'success',
			detail: 'Maya completed password setup.'
		},
		warning: {
			title: 'Background work needs review',
			detail: 'A safe retry is waiting for an owner to inspect the sanitized failure details.',
			tone: 'warning'
		},
		commercial: {
			packageName: 'Growth',
			packageVersion: 'Growth · v3',
			paidThrough: 'September 30, 2026',
			grace: 'Not in grace',
			freeAccess: 'Paid access',
			exception: 'No active exceptions'
		},
		integrations: [
			{
				name: 'SMS and phone',
				state: 'Ready',
				tone: 'success',
				detail: 'Assigned number and credits are healthy.',
				nextAction: 'No action needed'
			},
			{
				name: 'Email',
				state: 'Retry waiting',
				tone: 'warning',
				detail: 'One setup-email delivery task needs review.',
				nextAction: 'Owner review required'
			},
			{
				name: 'Payments',
				state: 'Ready',
				tone: 'success',
				detail: 'Account readiness was last checked today.',
				nextAction: 'No action needed'
			},
			{
				name: 'Webchat',
				state: 'Not enabled',
				tone: 'inactive',
				detail: 'Package eligibility is available.',
				nextAction: 'Contractor can enable it'
			}
		],
		history: [
			{
				at: 'Today · 10:01',
				title: 'Setup email delivery failed',
				detail: 'Failure is sanitized and tied to correlation ID dev-setup-184.',
				tone: 'warning'
			},
			{
				at: 'Today · 09:53',
				title: 'Recovery item created',
				detail: 'The failure appears in the global and organization recovery views.',
				tone: 'informative'
			}
		],
		recovery: {
			state: 'Pending review',
			tone: 'warning',
			detail:
				'Attempt 1 failed. Retry is disabled in this preview and will be idempotent when connected.'
		}
	}
};

export const organizationDetailScenarios = Object.keys(scenarios) as OrganizationDetailScenario[];

export function getOrganizationDetailPreview(
	scenario: string | null | undefined
): OrganizationDetailPreview {
	return scenarios[(scenario ?? 'active') as OrganizationDetailScenario] ?? scenarios.active;
}

export function organizationDetailScenarioLabel(scenario: OrganizationDetailScenario) {
	return scenario.replaceAll('-', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());
}
