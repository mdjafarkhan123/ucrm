import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import {
	PRIVATE_READ_HEADERS,
	databaseError,
	unauthorized,
	validationError
} from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Which address an email preview will say it comes "From". The enqueue functions own the real choice and check
// it again at send time; this read reaches the same answer two ways:
// - `manual` -- a message or inbox reply. manual_email_sender_preview calls the very resolver the enqueue
//   functions call (enqueue_manual_communication_email, enqueue_conversation_reply_email), which prefers the
//   writer's own sender and falls back to the business address, so the preview cannot disagree with the send.
// - `business` -- a quote, invoice or receipt goes from the business's default automated sender
//   (enqueue_quote_communication_email, enqueue_invoice_communication_email); that rule is a single filter and
//   is still mirrored here.
// A sender whose domain is not fully verified cannot send, so it resolves to null here as it fails there.
// The owner client is needed because domain readiness is only visible to connection managers under RLS;
// the reply names nothing beyond the address a customer would see on the email itself.
export const GET: RequestHandler = async (event) => {
	const context = await requireOrganization(event);
	if (!context) return unauthorized();

	const kind = event.url.searchParams.get('kind');
	if (kind !== 'manual' && kind !== 'business') {
		return validationError({ kind: 'Choose manual or business.' });
	}

	const client = getOwnerSupabaseClient();

	if (kind === 'manual') {
		const { data, error } = await client
			.rpc('manual_email_sender_preview', {
				target_organization_id: context.organization.id,
				target_actor_user_id: context.user.id
			})
			.maybeSingle();
		if (error) return databaseError();
		return json({ sender: data ?? null }, { headers: PRIVATE_READ_HEADERS });
	}

	const { data: sender, error } = await client
		.from('communication_email_senders')
		.select('display_name, email_address, domain_id')
		.eq('organization_id', context.organization.id)
		.eq('lifecycle_state', 'enabled')
		.eq('allows_automated', true)
		.eq('is_organization_default', true)
		.order('created_at')
		.order('id')
		.limit(1)
		.maybeSingle();
	if (error) return databaseError();
	if (!sender) return json({ sender: null }, { headers: PRIVATE_READ_HEADERS });

	const { data: domain, error: domainError } = await client
		.from('communication_email_domains')
		.select('id')
		.eq('organization_id', context.organization.id)
		.eq('id', sender.domain_id)
		.eq('purpose', 'sending')
		.eq('lifecycle_state', 'verified')
		.eq('provider_verified', true)
		.eq('provider_authenticated', true)
		.eq('ownership_status', 'passing')
		.eq('dkim_status', 'passing')
		.maybeSingle();
	if (domainError) return databaseError();

	return json(
		{
			sender: domain
				? { display_name: sender.display_name, email_address: sender.email_address }
				: null
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
