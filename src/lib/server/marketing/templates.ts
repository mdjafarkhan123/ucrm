import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import type { MarketingEmailTemplate, MarketingPlatformTemplate } from '$lib/marketing/templates';

// The starter template library: Jafar's platform templates (read-only from the app's point of view -- no
// editor UI yet) and an organization's own copies of them. Copying snapshots blocks/subject/preview_text
// plus the platform template's current version; later platform edits never touch the copy, matching
// communications_email_templates' relationship to platform_email_templates.

export class TemplateNotFoundError extends Error {}

export async function listPlatformTemplates(): Promise<MarketingPlatformTemplate[]> {
	const owner = getOwnerSupabaseClient();
	const { data, error } = await owner
		.from('marketing_platform_templates')
		.select('id, key, name, goal, subject, preview_text, blocks, version')
		.order('name');
	if (error) throw error;
	return (data ?? []) as MarketingPlatformTemplate[];
}

export async function listOrganizationTemplates(
	organizationId: string
): Promise<MarketingEmailTemplate[]> {
	const owner = getOwnerSupabaseClient();
	const { data, error } = await owner
		.from('marketing_email_templates')
		.select(
			'id, source_template_id, source_version_copied_at, name, subject, preview_text, blocks, updated_at'
		)
		.eq('organization_id', organizationId)
		.order('name');
	if (error) throw error;
	return (data ?? []) as MarketingEmailTemplate[];
}

// Copies one platform template into the organization's own library. Reads the platform template with the
// same service-role client that will write the copy, so the snapshot is atomic from the caller's point of
// view even without a single SQL statement doing both.
export async function copyPlatformTemplate(
	organizationId: string,
	userId: string,
	platformTemplateKey: string
): Promise<MarketingEmailTemplate> {
	const owner = getOwnerSupabaseClient();
	const { data: source, error: sourceError } = await owner
		.from('marketing_platform_templates')
		.select('id, name, subject, preview_text, blocks, version')
		.eq('key', platformTemplateKey)
		.maybeSingle();
	if (sourceError) throw sourceError;
	if (!source) throw new TemplateNotFoundError();

	const { data, error } = await owner
		.from('marketing_email_templates')
		.insert({
			organization_id: organizationId,
			source_template_id: source.id,
			source_version_copied_at: source.version,
			name: source.name,
			subject: source.subject,
			preview_text: source.preview_text,
			blocks: source.blocks,
			created_by: userId
		})
		.select(
			'id, source_template_id, source_version_copied_at, name, subject, preview_text, blocks, updated_at'
		)
		.single();
	if (error) throw error;
	return data as MarketingEmailTemplate;
}
