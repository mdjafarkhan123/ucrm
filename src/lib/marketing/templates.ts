import type { MarketingBlock, MarketingGoal } from './campaign-content';

// A platform starter template (Jafar-managed) or an organization's own copy of one. Both carry the same
// content shape (subject, preview_text, blocks); an organization copy additionally remembers where it came
// from and which platform version it copied, so the picker can say "a newer version of this exists" without
// a sync job -- mirrors communications_email_templates' relationship to platform_email_templates.

export type MarketingPlatformTemplate = {
	id: string;
	key: string;
	name: string;
	goal: MarketingGoal | null;
	subject: string;
	preview_text: string | null;
	blocks: MarketingBlock[];
	version: number;
};

export type MarketingEmailTemplate = {
	id: string;
	source_template_id: string | null;
	source_version_copied_at: number | null;
	name: string;
	subject: string;
	preview_text: string | null;
	blocks: MarketingBlock[];
	updated_at: string;
};
