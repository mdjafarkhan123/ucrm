import { z } from 'zod';
import type { RequestHandler } from './$types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { createSupabaseTwilioProvisioningStore } from '$lib/server/communications/twilio-provisioning-store';
import {
	collectTwilioValidationTokens,
	getTwilioNumberPaperworkWebhookUrl,
	validateTwilioSignature
} from '$lib/server/communications/twilio-webhook';
import {
	createNumberPaperworkDeps,
	syncNumberPaperwork
} from '$lib/server/communications/sms-number-paperwork';

// Stage 10 Part 3: Twilio calls this whenever a business's paperwork (a Regulatory Bundle) changes status --
// approved, or rejected with its reason. It is a signed classic webhook from the business's own subaccount,
// validated like the message status callback. The body only says which bundle to look at: the status itself
// is read back from Twilio, so a replayed or reordered callback can never set the wrong outcome. A daily check
// (trust-hub-status-cron) catches any callback that never arrives.

const NO_STORE = { 'cache-control': 'no-store' } as const;
const accepted = () => new Response(null, { status: 204, headers: NO_STORE });
const forbidden = () => new Response(null, { status: 403, headers: NO_STORE });
// Real but not yet recorded: ask Twilio to send it again.
const retryLater = () => new Response(null, { status: 500, headers: NO_STORE });

const paramsSchema = z.object({
	AccountSid: z.string().regex(/^AC[0-9A-Fa-f]{32}$/),
	BundleSid: z.string().regex(/^BU[0-9A-Fa-f]{32}$/),
	FailureReason: z.string().max(4000).optional()
});

export const POST: RequestHandler = async ({ request }) => {
	let params: Record<string, string>;
	try {
		const form = await request.formData();
		params = {};
		for (const [key, value] of form.entries()) if (typeof value === 'string') params[key] = value;
	} catch {
		return forbidden();
	}
	// Twilio's docs spell the fields both ways (BundleSID, BundleSid); read either.
	const identifiers = paramsSchema.safeParse({
		AccountSid: params.AccountSid ?? params.AccountSID,
		BundleSid: params.BundleSid ?? params.BundleSID,
		FailureReason: params.FailureReason || undefined
	});
	if (!identifiers.success) return forbidden();

	const client = getOwnerSupabaseClient();
	const provisioning = createSupabaseTwilioProvisioningStore(client);
	const account = await provisioning.getAccountBySubaccountSid(identifiers.data.AccountSid);
	if (!account) return forbidden();
	const tokens = await collectTwilioValidationTokens(provisioning, account.id, {
		organizationId: account.organizationId,
		subaccountSid: account.subaccountSid
	});
	const valid = validateTwilioSignature(
		tokens,
		request.headers.get('x-twilio-signature'),
		getTwilioNumberPaperworkWebhookUrl(),
		params
	);
	if (!valid) return forbidden();

	const deps = createNumberPaperworkDeps();
	const set = await deps.store.findByBundleSid(identifiers.data.BundleSid).catch(() => undefined);
	if (set === undefined) return retryLater();
	// A bundle this app never made, or another business's: nothing to do.
	if (!set || set.organizationId !== account.organizationId) return accepted();

	try {
		await syncNumberPaperwork(deps, {
			organizationId: set.organizationId,
			paperworkId: set.id,
			callbackReason: identifiers.data.FailureReason ?? null
		});
		return accepted();
	} catch (error) {
		console.error('Could not follow a paperwork status callback.', {
			paperworkId: set.id,
			error: error instanceof Error ? error.message : error
		});
		return retryLater();
	}
};
