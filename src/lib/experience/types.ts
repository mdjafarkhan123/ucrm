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
