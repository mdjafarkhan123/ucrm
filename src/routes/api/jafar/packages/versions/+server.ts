import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { packageVersionWriteSchema } from '$lib/server/validation/package.schema';

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = packageVersionWriteSchema.safeParse(body);
	if (!parsed.success) {
		return json({ error: 'Please review the package version details.' }, { status: 422 });
	}

	try {
		const input = parsed.data;
		const { data, error } = await getOwnerSupabaseClient().rpc('manage_platform_package_version', {
			operation: input.version_id ? 'update_draft' : 'create_draft',
			target_package_key: input.package_key,
			target_version_id: input.version_id,
			target_display_name: input.display_name,
			target_public_description: input.public_description,
			target_value_explanation: input.value_explanation ?? undefined,
			target_price_usd_cents: input.price_usd_cents,
			target_feature_keys: input.feature_keys,
			target_limit_state: input.limit?.state ?? undefined,
			target_limit_value: input.limit?.value ?? undefined,
			actor_email: session.email
		});
		if (error) {
			console.error('Owner package version operation was rejected.', error);
			return json({ error: 'The package version could not be saved.' }, { status: 409 });
		}
		const emailAllowances = input.email_allowances;
		if (emailAllowances) {
			const { error: allowanceError } = await getOwnerSupabaseClient().rpc(
				'manage_platform_package_email_allowances',
				{
					target_version_id: data,
					target_operational_state: emailAllowances.operational.state,
					target_operational_value: emailAllowances.operational.value as number,
					target_essential_state: emailAllowances.essential.state,
					target_essential_value: emailAllowances.essential.value as number,
					actor_email: session.email
				}
			);
			if (allowanceError) {
				console.error('Owner package email allowance operation was rejected.', allowanceError);
				return json({ error: 'The package version could not be saved.' }, { status: 409 });
			}
		}
		const websiteChatLimits = input.website_chat_limits;
		if (websiteChatLimits) {
			const { error: websiteChatError } = await getOwnerSupabaseClient().rpc(
				'manage_platform_package_website_chat_limits',
				{
					target_version_id: data,
					target_widgets_state: websiteChatLimits.widgets.state,
					target_widgets_value: websiteChatLimits.widgets.value as number,
					target_accepted_conversations_state: websiteChatLimits.accepted_conversations.state,
					target_accepted_conversations_value: websiteChatLimits.accepted_conversations
						.value as number,
					actor_email: session.email
				}
			);
			if (websiteChatError) {
				console.error('Owner package Website Chat limit operation was rejected.', websiteChatError);
				return json({ error: 'The package version could not be saved.' }, { status: 409 });
			}
		}
		return json({ version_id: data, saved: true });
	} catch (error) {
		console.error('Could not save owner package version.', error);
		return json({ error: 'The package version could not be saved.' }, { status: 500 });
	}
};
