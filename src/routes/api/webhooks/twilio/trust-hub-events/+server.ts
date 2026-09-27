import { timingSafeEqual } from 'node:crypto';
import type { RequestHandler } from './$types';
import { getServerEnv } from '$lib/server/env';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { createSupabaseTrustHubSubmissionStore } from '$lib/server/communications/trust-hub-submission-store';
import {
	createTwilioTrustHubClient,
	TwilioTrustHubError
} from '$lib/server/communications/twilio-trust-hub';
import { createSupabaseTrustHubStatusTriggerStore } from '$lib/server/communications/trust-hub-status-trigger-store';
import { syncTrustHubRegistrationStatus } from '$lib/server/communications/trust-hub-submission';

// Stage 9D primary trigger: Twilio Event Streams pushes Brand/Campaign status changes here instead of us
// polling for them (Twilio's own recommendation -- see the migration's header comment). Event Streams webhook
// (Underscore-prefixed: SvelteKit refuses any other non-handler export from a route file.)
// Sinks authenticate via HTTP Basic auth credentials embedded in the Sink's destination URL, not an
// X-Twilio-Signature header like classic Twilio webhooks (confirmed against Twilio's Webhook Quickstart,
// 2026-09-15) -- so this route's auth model deliberately differs from status/+server.ts's signature check.
// The Sink must be created (once, for the whole platform account -- every contractor's Brand/Campaign lives
// under our single ISV account) pointing at:
//   https://<_TRUST_HUB_EVENTS_WEBHOOK_USERNAME>:<TRUST_HUB_EVENTS_WEBHOOK_SECRET>@<host>/api/webhooks/twilio/trust-hub-events
// subscribed to the nine A2P Brand/Campaign registration event types, with Batch set to false so each delivery
// carries one event. That Sink/Subscription creation is a real (free) action on the live Twilio account and is
// Jafar's to do, not automated here.
export const _TRUST_HUB_EVENTS_WEBHOOK_USERNAME = 'ucrm-trust-hub-events';

const BRAND_EVENT_TYPES = new Set([
	'com.twilio.messaging.compliance.brand-registration.brand-registered',
	'com.twilio.messaging.compliance.brand-registration.brand-failure',
	'com.twilio.messaging.compliance.brand-registration.brand-verified',
	'com.twilio.messaging.compliance.brand-registration.brand-unverified',
	'com.twilio.messaging.compliance.brand-registration.brand-vetted-verified',
	'com.twilio.messaging.compliance.brand-registration.brand-secondary-vetting-failure'
]);

const CAMPAIGN_EVENT_TYPES = new Set([
	'com.twilio.messaging.compliance.campaign-registration.campaign-submitted',
	'com.twilio.messaging.compliance.campaign-registration.campaign-failure',
	'com.twilio.messaging.compliance.campaign-registration.campaign-approved'
]);

const NO_STORE = { 'cache-control': 'no-store' } as const;
// Accepted (processed, or a harmless unknown/already-resolved event). Twilio needs no body.
const accepted = () => new Response(null, { status: 204, headers: NO_STORE });
// Auth failed, or the body wasn't a recognizable CloudEvents array -- never say why.
const forbidden = () => new Response(null, { status: 403, headers: NO_STORE });
// A transient failure while syncing -- ask Twilio to redeliver (Event Streams is at-least-once, queued up to
// four hours). Safe: syncTrustHubRegistrationStatus re-fetches rather than re-creates on every call.
const retryLater = () => new Response(null, { status: 500, headers: NO_STORE });

function isAuthorized(request: Request): boolean {
	const expected = getServerEnv().TRUST_HUB_EVENTS_WEBHOOK_SECRET;
	if (!expected) return false;
	const header = request.headers.get('authorization') ?? '';
	const [scheme, encoded] = header.split(' ');
	if (scheme !== 'Basic' || !encoded) return false;

	let decoded: string;
	try {
		decoded = Buffer.from(encoded, 'base64').toString('utf8');
	} catch {
		return false;
	}
	const expectedCredentials = `${_TRUST_HUB_EVENTS_WEBHOOK_USERNAME}:${expected}`;
	const provided = Buffer.from(decoded);
	const wanted = Buffer.from(expectedCredentials);
	return provided.length === wanted.length && timingSafeEqual(provided, wanted);
}

type CloudEvent = { type?: unknown; data?: unknown };

function parseData(raw: unknown): Record<string, unknown> | null {
	// Twilio's own CloudEvents examples are inconsistent about whether `data` is an inline object or a
	// JSON-encoded string, so both are accepted rather than assuming one.
	const value = typeof raw === 'string' ? safeJsonParse(raw) : raw;
	return value && typeof value === 'object' ? (value as Record<string, unknown>) : null;
}

function safeJsonParse(raw: string): unknown {
	try {
		return JSON.parse(raw);
	} catch {
		return null;
	}
}

function extractResourceSid(
	event: CloudEvent
): { role: 'brand_registration' | 'campaign'; sid: string } | null {
	if (typeof event.type !== 'string') return null;
	const data = parseData(event.data);
	if (!data) return null;

	if (BRAND_EVENT_TYPES.has(event.type)) {
		const sid = data.brandsid;
		return typeof sid === 'string' && sid ? { role: 'brand_registration', sid } : null;
	}
	if (CAMPAIGN_EVENT_TYPES.has(event.type)) {
		const sid = data.campaignsid;
		return typeof sid === 'string' && sid ? { role: 'campaign', sid } : null;
	}
	// A recognized-but-unwired A2P event (e.g. phone number registration) or an event type Twilio adds later --
	// nothing to do with it yet.
	return null;
}

export const POST: RequestHandler = async ({ request }) => {
	if (!isAuthorized(request)) return forbidden();

	let events: CloudEvent[];
	try {
		const body = await request.json();
		if (!Array.isArray(body)) return forbidden();
		events = body;
	} catch {
		return forbidden();
	}

	const client = getOwnerSupabaseClient();
	const triggerStore = createSupabaseTrustHubStatusTriggerStore(client);
	const deps = {
		store: createSupabaseTrustHubSubmissionStore(client),
		twilio: createTwilioTrustHubClient()
	};

	let sawRetryableFailure = false;

	for (const event of events) {
		const resource = extractResourceSid(event);
		if (!resource) continue;

		const registrationId = await triggerStore.findRegistrationIdByResourceSid(
			resource.role,
			resource.sid
		);
		if (!registrationId) {
			console.warn('Trust Hub event for an unknown resource SID; ignoring.', {
				role: resource.role,
				eventType: event.type
			});
			continue;
		}

		try {
			await syncTrustHubRegistrationStatus(deps, { registrationId });
		} catch (error) {
			if (error instanceof TwilioTrustHubError && error.retryable) {
				sawRetryableFailure = true;
				console.error('Trust Hub status sync failed (retryable); asking Twilio to redeliver.', {
					registrationId,
					error: error.message
				});
				continue;
			}
			// Non-retryable: a redelivery would fail identically, so log for investigation and move on rather
			// than blocking the rest of this batch.
			console.error('Trust Hub status sync failed (not retryable); accepting the event anyway.', {
				registrationId,
				error: error instanceof Error ? error.message : error
			});
		}
	}

	return sawRetryableFailure ? retryLater() : accepted();
};
