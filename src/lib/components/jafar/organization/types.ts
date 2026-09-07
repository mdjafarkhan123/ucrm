export type PackageKey = 'starter' | 'growth' | 'elite';

export type EffectiveAccess = {
	organization: { id: string; name: string; slug: string; lifecycle_status: string };
	billing: {
		paid_through_date: string | null;
		paid_through_source: string | null;
		grace_ends_at: string | null;
		is_overdue: boolean;
		is_in_grace: boolean;
	};
	package: {
		current_key: PackageKey;
		effective_key: PackageKey;
		version_id: string | null;
		version_number: number | null;
		status: 'draft' | 'published' | 'retired';
		display_name: string;
		public_description: string | null;
		price_usd_cents: number | null;
		currency: string;
		billing_period: string;
		scheduled_key: PackageKey | null;
		scheduled_effective_at: string | null;
	};
	features: Record<string, boolean>;
	package_features: Record<string, boolean>;
	feature_overrides: Record<
		string,
		{
			state: 'on' | 'off';
			starts_at: string;
			expires_at: string | null;
			reason: string | null;
			is_legacy_import: boolean;
		}
	>;
	limits: Record<
		'employee_seats' | 'website_chat_widgets',
		{
			state: 'unlimited' | 'not_included' | 'numeric';
			value: number | null;
			is_unlimited: boolean;
			source: 'package' | 'override';
		}
	>;
	free_access: {
		active: { grant_id: string; starts_at: string; access_until_date: string | null } | null;
		future: { grant_id: string; starts_at: string; access_until_date: string | null } | null;
	};
};
export type AccessResponse = { access: EffectiveAccess; error?: string };
export type CommercialState = {
	organization: { id: string; name: string; lifecycle_status: string };
	state: {
		paid_through_date: string | null;
		paid_through_source: string | null;
		grace_ends_at: string | null;
	} | null;
	settings: { commercial_timezone: string; timezone_source: string } | null;
	original_events: {
		id: string;
		event_kind: string;
		occurred_at: string;
		summary: string;
		amount_usd_cents: number | null;
		paid_through_after: string | null;
		private_reference: string | null;
	}[];
	closure: { id: string; reason: string; started_at: string; deadline_at: string } | null;
	error?: string;
};

export type PublishedVersion = {
	id: string;
	display_name: string;
	version_number: number;
	status: string;
	price_usd_cents: number;
	currency: string;
	billing_period: string;
};
export type PackagesCatalogResponse = {
	packages: { package_key: PackageKey; display_name: string; versions: PublishedVersion[] }[];
	error?: string;
};

export type TeamMember = {
	user_id: string;
	role: string;
	created_at: string;
	full_name: string | null;
	email: string | null;
	permission_overrides: { permission_key: string; override_state: string }[];
};
export type TeamResponse = {
	organization: { id: string; name: string };
	members: TeamMember[];
	has_administrator: boolean;
	error?: string;
};

export type HistoryEvent = {
	id: string;
	event_type: string;
	target_type: string;
	target_key: string | null;
	actor_email: string | null;
	occurred_at: string;
};
export type HistoryResponse = {
	organization: { id: string; name: string };
	events: HistoryEvent[];
	applicationId: string | null;
	error?: string;
};

export type OperationAttempt = {
	id: string;
	operation_type: string;
	target_kind: string;
	target_id: string;
	status: string;
	attempt_count: number;
	last_error: string | null;
	updated_at: string;
};
export type OperationListResponse = {
	operations: OperationAttempt[];
	error?: string;
};

export type MutationResponse = { error?: string };
