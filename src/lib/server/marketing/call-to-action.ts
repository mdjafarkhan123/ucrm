import { createHash, randomBytes } from 'node:crypto';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import type { MarketingCta } from '$lib/marketing/campaign-content';
import type { FormOutcome } from '$lib/forms/types';

// The campaign's primary action (blueprint §8 step 4), resolved from the records that own each fact at send
// time: the chosen form's public address, or the Business Profile's website or phone. A target that no
// longer exists (form unpublished, phone removed) resolves to null and the email goes out without the button
// rather than with a broken one.
//
// A form link carries an opaque recipient-bound token (M5a), so a Request submitted through it is this
// campaign's direct tracked result (blueprint §13). Like the unsubscribe token, it is 32 random bytes that
// encode no id, and only its hash reaches the database.

export type MarketingCtaTarget = {
	type: MarketingCta['type'];
	label: string;
	url: string;
};

const FORM_LABELS: Record<FormOutcome, string> = {
	request: 'Request service',
	assessment: 'Book an assessment',
	job: 'Book now'
};

// The query parameter the public form reads the token from in M5b.
export const MARKETING_CTA_TOKEN_PARAM = 'mc';

const TOKEN_BYTES = 32;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

function hashLiteral(token: string) {
	return `\\x${createHash('sha256').update(token, 'utf8').digest('hex')}`;
}

export function createMarketingCtaToken() {
	const token = randomBytes(TOKEN_BYTES).toString('base64url');
	return { token, tokenHash: hashLiteral(token) };
}

export function marketingCtaTokenHash(token: string | null | undefined) {
	if (!token || !TOKEN_PATTERN.test(token)) return null;
	return hashLiteral(token);
}

/** Binds a resolved form target to one recipient. Website and phone targets carry no token. */
export function withRecipientToken(target: MarketingCtaTarget, token: string): MarketingCtaTarget {
	if (target.type !== 'internal_form') return target;
	const url = new URL(target.url);
	url.searchParams.set(MARKETING_CTA_TOKEN_PARAM, token);
	return { ...target, url: url.toString() };
}

function websiteUrl(website: string): string | null {
	const candidate = /^https?:\/\//i.test(website) ? website : `https://${website}`;
	try {
		return new URL(candidate).toString();
	} catch {
		return null;
	}
}

function phoneUrl(phone: string): string | null {
	const dialable = phone.replace(/[^\d+]/g, '');
	return dialable.replace(/\+/g, '').length >= 5 ? `tel:${dialable}` : null;
}

export async function resolveMarketingCtaTarget(
	organizationId: string,
	cta: MarketingCta | null | undefined,
	origin: string
): Promise<MarketingCtaTarget | null> {
	if (!cta) return null;
	const owner = getOwnerSupabaseClient();

	if (cta.type === 'internal_form') {
		const [organization, form] = await Promise.all([
			owner.from('organizations').select('slug').eq('id', organizationId).single(),
			owner
				.from('forms')
				.select('public_slug, outcome, current_published_version_id')
				.eq('organization_id', organizationId)
				.eq('id', cta.form_id)
				.eq('is_enabled', true)
				.is('archived_at', null)
				.maybeSingle()
		]);
		if (organization.error) throw organization.error;
		if (form.error) throw form.error;
		if (!form.data?.current_published_version_id || !organization.data?.slug) return null;
		return {
			type: 'internal_form',
			label: FORM_LABELS[form.data.outcome as FormOutcome] ?? 'Get started',
			url: `${origin}/forms/${encodeURIComponent(organization.data.slug)}/${encodeURIComponent(form.data.public_slug)}`
		};
	}

	const { data, error } = await owner
		.from('organization_settings')
		.select('phone, website')
		.eq('organization_id', organizationId)
		.maybeSingle();
	if (error) throw error;

	if (cta.type === 'website') {
		const url = data?.website ? websiteUrl(data.website.trim()) : null;
		return url ? { type: 'website', label: 'Visit our website', url } : null;
	}

	const url = data?.phone ? phoneUrl(data.phone) : null;
	return url ? { type: 'phone', label: 'Call us', url } : null;
}
