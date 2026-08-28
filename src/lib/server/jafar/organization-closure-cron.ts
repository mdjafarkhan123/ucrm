import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { enqueueEmailDelivery } from '$lib/server/events/dispatcher';
import { recordOperationOutcome } from '$lib/server/events/outbox';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';
import { renderTemplate, htmlToPlainText } from '$lib/server/jafar/message-templates';
import {
	BrevoManagementError,
	deleteBrevoDomainById,
	deleteBrevoSender
} from '$lib/server/communications/brevo';

type NoticeKind =
	'closure_started' | 'fourteen_day_reminder' | 'three_day_reminder' | 'closure_completed';

/**
 * The "closure_started" notice is sent synchronously from the closure-start route the moment
 * closure begins (step 9) -- it isn't date-driven, so it is never found "due" by this daily sweep,
 * but it shares sendClosureNotice's claim-then-send shape below (exported for that route to reuse).
 * Template keys are step 11's job to actually publish; until then a due notice is recorded as
 * skipped with a clear reason rather than crashing the sweep for every other organization.
 */
const NOTICE_TEMPLATE_KEYS: Record<NoticeKind, string> = {
	closure_started: 'organization_closure_started',
	fourteen_day_reminder: 'organization_closure_fourteen_day_reminder',
	three_day_reminder: 'organization_closure_three_day_reminder',
	closure_completed: 'organization_closure_completed'
};

type ClosureRecordRow = { id: string; organization_id: string; deadline_at: string };
type PendingAuthCleanupRow = { operation_id: string; pending_auth_user_ids: string[] };
type ProviderResource = { kind: 'domain' | 'sender'; provider_id: string };
type PendingProviderCleanupRow = {
	operation_id: string;
	pending_provider_resources: ProviderResource[];
};

export type NoticeOutcome =
	| { sent: true }
	| { sent: false; reason: 'already_claimed' | 'no_recipient' | 'template_not_published' };

export type ClosureCronResult = {
	noticesSent: number;
	noticesSkipped: number;
	purgesCompleted: number;
	purgesFailed: number;
	authCleanupsCompleted: number;
	authCleanupsFailed: number;
	providerCleanupsCompleted: number;
	providerCleanupsFailed: number;
};

/**
 * The receipt's top-level status reflects the WHOLE purge, including its two external cleanup legs
 * (Auth users and Brevo provider resources). It is complete only once every applicable component has
 * succeeded; a single failed leg makes it failed_partial, and anything still pending keeps it
 * in_progress. Components neither leg touched are absent from the map, which counts as done. Only the
 * completed state carries a completed_at, matching the receipt table's own check constraint.
 */
function nextReceiptState(components: Record<string, string>): {
	status: 'in_progress' | 'failed_partial' | 'completed';
	completed_at: string | null;
} {
	const externalLegs = [components.auth_users, components.provider_resources];
	if (externalLegs.includes('failed')) return { status: 'failed_partial', completed_at: null };
	if (externalLegs.includes('pending')) return { status: 'in_progress', completed_at: null };
	return { status: 'completed', completed_at: new Date().toISOString() };
}

async function resolveOrganizationContext(
	client: SupabaseClient<Database>,
	organizationId: string
) {
	const [{ data: organization }, { data: ownerMember }] = await Promise.all([
		client.from('organizations').select('name').eq('id', organizationId).maybeSingle(),
		client
			.from('organization_members')
			.select('user_id')
			.eq('organization_id', organizationId)
			.eq('role', 'owner')
			.maybeSingle()
	]);
	if (!organization || !ownerMember) return null;

	const { data: userResult } = await client.auth.admin.getUserById(ownerMember.user_id);
	const email = userResult?.user?.email;
	if (!email) return null;

	return { businessName: organization.name, recipientEmail: email };
}

/**
 * Claims a notice for a closure record before sending it: the insert into
 * organization_closure_notices is the actual race guard (its unique (closure_record_id,
 * notice_kind) index rejects a concurrent second claim), not a prior SELECT check, so this stays
 * correct even under a genuine double-run of the daily job. enqueueEmailDelivery's own
 * idempotency key is a second, independent guard against ever sending the same notice twice.
 */
export async function sendClosureNotice(
	client: SupabaseClient<Database>,
	params: {
		closureRecordId: string;
		organizationId: string;
		noticeKind: NoticeKind;
		mergeValues: Record<string, string>;
	}
): Promise<NoticeOutcome> {
	const { data: existingNotice } = await client
		.from('organization_closure_notices')
		.select('id')
		.eq('closure_record_id', params.closureRecordId)
		.eq('notice_kind', params.noticeKind)
		.maybeSingle();
	if (existingNotice) return { sent: false, reason: 'already_claimed' };

	const context = await resolveOrganizationContext(client, params.organizationId);
	if (!context) return { sent: false, reason: 'no_recipient' };

	const templateKey = NOTICE_TEMPLATE_KEYS[params.noticeKind];
	const { data: template } = await client
		.from('platform_message_templates')
		.select('subject_published, body_published')
		.eq('template_key', templateKey)
		.maybeSingle();
	if (!template?.body_published) return { sent: false, reason: 'template_not_published' };

	const values = { business_name: context.businessName, ...params.mergeValues };
	const subject = renderTemplate(template.subject_published ?? '', values);
	const body = renderTemplate(template.body_published, values);

	const deliveryId = await enqueueEmailDelivery(client, {
		templateKey,
		target: { targetKind: 'organization', targetId: params.organizationId },
		idempotencyKey: `closure:${params.closureRecordId}:${params.noticeKind}`,
		recipientEmail: context.recipientEmail,
		subject,
		htmlContent: body,
		textContent: htmlToPlainText(body)
	});

	const { error: claimError } = await client.from('organization_closure_notices').insert({
		closure_record_id: params.closureRecordId,
		notice_kind: params.noticeKind,
		outbox_delivery_id: deliveryId
	});
	// 23505 = unique_violation: another concurrent run already claimed this notice. The email was
	// still sent (or reused via the idempotency key above), which is fine -- the claim race losing
	// is expected, not an error.
	if (claimError && claimError.code !== '23505') throw claimError;

	return { sent: true };
}

/**
 * Deletes the given Auth users and reconciles the receipt's "auth_users" component. Shared by the
 * happy path (right after a successful purge) and the resume path (a later sweep finding a receipt
 * whose pending_auth_user_ids was never cleared). "Not found" on delete is treated as success --
 * the user is gone either way, whether this call or an earlier interrupted one removed it.
 */
async function finishAuthCleanup(
	client: SupabaseClient<Database>,
	params: { operationId: string; pendingUserIds: string[] }
) {
	const idempotencyKey = `organization_purge_auth_cleanup:${params.operationId}`;
	const target = { targetKind: 'platform' as const, targetId: null };

	const failures: string[] = [];
	for (const userId of params.pendingUserIds) {
		const { error } = await client.auth.admin.deleteUser(userId);
		if (error && !error.message.toLowerCase().includes('not found')) {
			failures.push(`${userId}: ${error.message}`);
		}
	}

	const { data: receipt } = await client
		.from('organization_deletion_receipts')
		.select('component_results')
		.eq('operation_id', params.operationId)
		.maybeSingle();
	const mergedComponents = {
		...((receipt?.component_results as Record<string, string> | null) ?? {}),
		auth_users: failures.length === 0 ? 'succeeded' : 'failed'
	};
	const receiptState = nextReceiptState(mergedComponents);

	const { error: updateError } = await client
		.from('organization_deletion_receipts')
		.update({
			component_results: mergedComponents,
			pending_auth_user_ids: failures.length === 0 ? null : params.pendingUserIds,
			status: receiptState.status,
			completed_at: receiptState.completed_at
		})
		.eq('operation_id', params.operationId);
	if (updateError) console.error('Could not update the deletion receipt.', updateError);

	if (failures.length > 0) {
		await recordOperationOutcome(client, {
			operationType: 'organization_purge',
			idempotencyKey,
			target,
			success: false,
			error: failures.join('; ')
		});
		await raiseOwnerAlert(client, {
			kind: 'organization_purge_failed',
			severity: 'urgent',
			title: 'A purged organization still has a login account that could not be removed',
			body: failures.join('; ').slice(0, 500),
			target
		}).catch((alertError) => console.error('Could not raise the purge-cleanup alert.', alertError));
		return false;
	}

	await recordOperationOutcome(client, {
		operationType: 'organization_purge',
		idempotencyKey,
		target,
		success: true
	});
	return true;
}

/**
 * Deletes the given Brevo provider resources and reconciles the receipt's "provider_resources"
 * component. Twin of finishAuthCleanup: shared by the happy path (right after a successful purge) and
 * the resume path (a later sweep finding a receipt whose pending_provider_resources was never
 * cleared). A resource Brevo no longer knows -- a 404, or an id absent from its domain list -- is
 * treated as success, since the goal is that the resource be gone. Every other error keeps the anchor
 * so the next sweep retries, and never lets the receipt reach completed.
 */
async function finishProviderCleanup(
	client: SupabaseClient<Database>,
	params: { operationId: string; resources: ProviderResource[] }
) {
	const idempotencyKey = `organization_purge_provider_cleanup:${params.operationId}`;
	const target = { targetKind: 'platform' as const, targetId: null };

	const failures: string[] = [];
	for (const resource of params.resources) {
		try {
			if (resource.kind === 'domain') {
				await deleteBrevoDomainById(resource.provider_id);
			} else {
				await deleteBrevoSender(Number(resource.provider_id));
			}
		} catch (error) {
			if (error instanceof BrevoManagementError && error.status === 404) continue;
			const reason = error instanceof Error ? error.message : 'unknown error';
			failures.push(`${resource.kind} ${resource.provider_id}: ${reason}`);
		}
	}

	const { data: receipt } = await client
		.from('organization_deletion_receipts')
		.select('component_results')
		.eq('operation_id', params.operationId)
		.maybeSingle();
	const mergedComponents = {
		...((receipt?.component_results as Record<string, string> | null) ?? {}),
		provider_resources: failures.length === 0 ? 'succeeded' : 'failed'
	};
	const receiptState = nextReceiptState(mergedComponents);

	const { error: updateError } = await client
		.from('organization_deletion_receipts')
		.update({
			component_results: mergedComponents,
			pending_provider_resources: failures.length === 0 ? null : params.resources,
			status: receiptState.status,
			completed_at: receiptState.completed_at
		})
		.eq('operation_id', params.operationId);
	if (updateError) console.error('Could not update the deletion receipt.', updateError);

	if (failures.length > 0) {
		await recordOperationOutcome(client, {
			operationType: 'organization_purge',
			idempotencyKey,
			target,
			success: false,
			error: failures.join('; ')
		});
		await raiseOwnerAlert(client, {
			kind: 'organization_purge_failed',
			severity: 'urgent',
			title: 'A purged organization still has provider resources that could not be removed',
			body: failures.join('; ').slice(0, 500),
			target
		}).catch((alertError) =>
			console.error('Could not raise the provider-cleanup alert.', alertError)
		);
		return false;
	}

	await recordOperationOutcome(client, {
		operationType: 'organization_purge',
		idempotencyKey,
		target,
		success: true
	});
	return true;
}

/**
 * Runs the SQL-side purge and, on success, its two external cleanup legs (Auth users and Brevo
 * provider resources). The completion notice is sent first: organization_closure_records and
 * organization_closure_notices both cascade away the moment the purge RPC commits, so that is the
 * last point either can be read or claimed.
 */
async function runScheduledPurge(client: SupabaseClient<Database>, record: ClosureRecordRow) {
	const sqlIdempotencyKey = `organization_purge:${record.organization_id}`;
	const sqlTarget = { targetKind: 'organization' as const, targetId: record.organization_id };

	await sendClosureNotice(client, {
		closureRecordId: record.id,
		organizationId: record.organization_id,
		noticeKind: 'closure_completed',
		mergeValues: {}
	}).catch((error) => console.error('Could not send the closure-completed notice.', error));

	const { data: purgeResult, error: purgeError } = await client.rpc('apply_organization_purge', {
		target_organization_id: record.organization_id,
		purge_trigger_kind: 'scheduled'
	});

	if (purgeError) {
		await recordOperationOutcome(client, {
			operationType: 'organization_purge',
			idempotencyKey: sqlIdempotencyKey,
			target: sqlTarget,
			success: false,
			error: purgeError.message
		});
		await raiseOwnerAlert(client, {
			kind: 'organization_purge_failed',
			severity: 'urgent',
			title: 'A scheduled organization purge failed',
			body: purgeError.message.slice(0, 500),
			target: sqlTarget
		}).catch((alertError) => console.error('Could not raise the purge-failure alert.', alertError));
		console.error('Could not purge the organization.', purgeError);
		return false;
	}

	await recordOperationOutcome(client, {
		operationType: 'organization_purge',
		idempotencyKey: sqlIdempotencyKey,
		target: sqlTarget,
		success: true
	});

	const applied = purgeResult as {
		applied: boolean;
		operation_id?: string;
		member_user_ids?: string[];
		provider_resources?: ProviderResource[];
	} | null;
	if (!applied?.applied || !applied.operation_id) return true;
	const operationId = applied.operation_id;

	// Both external legs are independent; each reads the freshest receipt and cannot mark it complete
	// while the other is still pending. A "purge" only counts as completed when both finish.
	const pendingUserIds = applied.member_user_ids ?? [];
	const providerResources = applied.provider_resources ?? [];

	const authOk =
		pendingUserIds.length === 0 ||
		(await finishAuthCleanup(client, { operationId, pendingUserIds }));
	const providerOk =
		providerResources.length === 0 ||
		(await finishProviderCleanup(client, { operationId, resources: providerResources }));

	return authOk && providerOk;
}

/**
 * Retries the external cleanup for one deletion receipt on demand -- the manual counterpart to the two
 * receipt passes in the daily sweep below, scoped to a single operation_id so the Jafar cleanup surface
 * can push a stuck (failed_partial) receipt without waiting for the next nightly run. It re-reads the
 * receipt's own anchors and runs only the legs still parked, so it is safe to press repeatedly and on a
 * receipt that another run already finished: cleared anchors mean skipped legs, and both finish helpers
 * treat an already-gone resource as success. retry_count is bumped once per manual press for the audit
 * trail; the finish helpers own every other receipt column.
 */
export async function retryReceiptCleanup(
	client: SupabaseClient<Database>,
	operationId: string
): Promise<{ found: boolean; authOk: boolean; providerOk: boolean }> {
	const { data: receipt, error } = await client
		.from('organization_deletion_receipts')
		.select('operation_id, retry_count, pending_auth_user_ids, pending_provider_resources')
		.eq('operation_id', operationId)
		.maybeSingle();
	if (error) throw error;
	if (!receipt) return { found: false, authOk: true, providerOk: true };

	await client
		.from('organization_deletion_receipts')
		.update({ retry_count: receipt.retry_count + 1 })
		.eq('operation_id', operationId);

	const pendingUserIds = receipt.pending_auth_user_ids ?? [];
	const providerResources = (receipt.pending_provider_resources ?? []) as ProviderResource[];

	const authOk =
		pendingUserIds.length === 0 ||
		(await finishAuthCleanup(client, { operationId, pendingUserIds }));
	const providerOk =
		providerResources.length === 0 ||
		(await finishProviderCleanup(client, { operationId, resources: providerResources }));

	return { found: true, authOk, providerOk };
}

/**
 * The daily sweep pg_cron triggers via the internal /api/jafar/internal/closure-cron route.
 * Three independent passes:
 *  1. Open closure windows -- send due reminders, and purge anything past its deadline.
 *  2. Deletion receipts whose Auth cleanup never finished last time.
 *  3. Deletion receipts whose provider (Brevo) cleanup never finished last time.
 * The receipt anchors (pending_auth_user_ids, pending_provider_resources) are the only remaining
 * handles once the organization -- and its closure record -- is already gone. Every pass is safe to
 * run again from scratch: every notice is claimed exactly once via a unique index, every purge call
 * is a harmless no-op once the organization no longer exists, and both external cleanups tolerate an
 * "already gone" resource as success.
 */
export async function runOrganizationClosureCron(
	client: SupabaseClient<Database>
): Promise<ClosureCronResult> {
	const result: ClosureCronResult = {
		noticesSent: 0,
		noticesSkipped: 0,
		purgesCompleted: 0,
		purgesFailed: 0,
		authCleanupsCompleted: 0,
		authCleanupsFailed: 0,
		providerCleanupsCompleted: 0,
		providerCleanupsFailed: 0
	};

	const { data: closureRecords, error: closureRecordsError } = await client
		.from('organization_closure_records')
		.select('id, organization_id, deadline_at')
		.eq('status', 'pending_closure');
	if (closureRecordsError) throw closureRecordsError;

	const now = Date.now();

	for (const record of (closureRecords ?? []) as ClosureRecordRow[]) {
		const deadline = new Date(record.deadline_at);
		const msRemaining = deadline.getTime() - now;

		if (msRemaining <= 0) {
			const purged = await runScheduledPurge(client, record);
			if (purged) result.purgesCompleted += 1;
			else result.purgesFailed += 1;
			continue;
		}

		const daysRemaining = Math.ceil(msRemaining / (24 * 60 * 60 * 1000));
		const deadlineDate = deadline.toISOString().slice(0, 10);

		if (daysRemaining <= 14) {
			const outcome = await sendClosureNotice(client, {
				closureRecordId: record.id,
				organizationId: record.organization_id,
				noticeKind: 'fourteen_day_reminder',
				mergeValues: { closure_deadline_at: deadlineDate }
			});
			if (outcome.sent) result.noticesSent += 1;
			else result.noticesSkipped += 1;
		}

		if (daysRemaining <= 3) {
			const outcome = await sendClosureNotice(client, {
				closureRecordId: record.id,
				organizationId: record.organization_id,
				noticeKind: 'three_day_reminder',
				mergeValues: { closure_deadline_at: deadlineDate }
			});
			if (outcome.sent) result.noticesSent += 1;
			else result.noticesSkipped += 1;
		}
	}

	const { data: unfinishedReceipts, error: unfinishedReceiptsError } = await client
		.from('organization_deletion_receipts')
		.select('operation_id, pending_auth_user_ids')
		.not('pending_auth_user_ids', 'is', null);
	if (unfinishedReceiptsError) throw unfinishedReceiptsError;

	for (const receipt of (unfinishedReceipts ?? []) as PendingAuthCleanupRow[]) {
		const ok = await finishAuthCleanup(client, {
			operationId: receipt.operation_id,
			pendingUserIds: receipt.pending_auth_user_ids
		});
		if (ok) result.authCleanupsCompleted += 1;
		else result.authCleanupsFailed += 1;
	}

	const { data: unfinishedProviderReceipts, error: unfinishedProviderReceiptsError } = await client
		.from('organization_deletion_receipts')
		.select('operation_id, pending_provider_resources')
		.not('pending_provider_resources', 'is', null);
	if (unfinishedProviderReceiptsError) throw unfinishedProviderReceiptsError;

	for (const receipt of (unfinishedProviderReceipts ?? []) as PendingProviderCleanupRow[]) {
		const resources = receipt.pending_provider_resources ?? [];
		if (resources.length === 0) continue;
		const ok = await finishProviderCleanup(client, {
			operationId: receipt.operation_id,
			resources
		});
		if (ok) result.providerCleanupsCompleted += 1;
		else result.providerCleanupsFailed += 1;
	}

	return result;
}
