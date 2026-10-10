/** What the Control Room's Experience tab reads (multi-industry foundation B1). */
export type ExperienceAgreementSummary = {
	id: string;
	package_name: string;
	effective_from: string;
};

export type ExperienceHistoryEntry = {
	id: string;
	experience_key: string;
	definition_version: number;
	business_type_key: string | null;
	service_shape: string;
	package_agreement_id: string | null;
	source: string;
	reason: string;
	actor_email: string;
	previous_decision_id: string | null;
	decided_at: string;
	experience_name: string | null;
	business_type_label: string | null;
	agreement: ExperienceAgreementSummary | null;
};

export type ConfirmableExperienceDefinition = {
	experience_key: string;
	version: number;
	name: string;
	capability_families: string[];
	business_types: { key: string; label: string }[];
};

export type ExperienceTabResponse = {
	profile: {
		/** `missing`, `unresolved` and `unrecognized` all mean no experience is enabled. */
		state: 'missing' | 'unresolved' | 'unrecognized' | 'confirmed';
		experience: string | null;
		decision_id: string | null;
	};
	history: ExperienceHistoryEntry[];
	definitions: ConfirmableExperienceDefinition[];
	current_agreement: ExperienceAgreementSummary | null;
	error?: string;
};

/** One answer that differs between today's access and the experience-aware access (multi-industry foundation B5). */
export type AccessChange = {
	key: string;
	direction: 'lost' | 'gained';
	/** Why the answer differs, in words Uplift can act on. */
	cause: string;
};

export type AccessDifferences = {
	features: AccessChange[];
	permissions: AccessChange[];
	navigation: AccessChange[];
};

export type AccessComparisonMember = {
	user_id: string;
	name: string | null;
	email: string | null;
	role: string;
	/** Permissions held today, and held once the experience takes part. */
	permissions_today: number;
	permissions_with_experience: number;
	differences: AccessDifferences;
};

export type AccessComparisonResponse = {
	/**
	 * `confirmed` compares against the reviewed profile; `planned` against the one experience the agreed
	 * edition is sold to (no profile yet); `unavailable` means there is nothing safe to compare against.
	 */
	basis: {
		state: 'confirmed' | 'planned' | 'unavailable';
		experience: string | null;
		experience_name: string | null;
		definition_version: number | null;
		explanation: string;
	};
	package_name: string | null;
	/** Capabilities the Package gives today, and how many stay on with the experience. */
	capabilities_today: number;
	capabilities_with_experience: number;
	organization: { features: AccessChange[] };
	members: AccessComparisonMember[];
	/** `same` only when every checked answer matches. */
	verdict: 'same' | 'different' | 'unavailable';
	error?: string;
};

/** What the Control Room's Readiness section reads for one business (multi-industry foundation B8). */
export type ReadinessHistoryEntry = {
	id: string;
	status: 'ready' | 'not_ready' | 'held';
	source: 'review' | 'carried_over';
	checks: { key: string; state: 'open' | 'done' | 'not_applicable'; note?: string }[];
	reason: string;
	business_message: string | null;
	actor_email: string;
	decided_at: string;
};

export type ReadinessAreaSummary = {
	key: string;
	label: string;
	opens: string;
	requires: string[];
	checks: { key: string; task: string; owner: 'business' | 'uplift' }[];
	/** The current decision, or null while Uplift has not reviewed the area. */
	current: ReadinessHistoryEntry | null;
	/** What the business sees right now, including an area held back by one it requires. */
	business_view: { state: string; open: boolean; sentence: string };
	history: ReadinessHistoryEntry[];
};

export type ReadinessTabResponse = {
	areas: ReadinessAreaSummary[];
	error?: string;
};
