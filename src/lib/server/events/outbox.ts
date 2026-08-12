import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import type { NotificationTargetKind, OperationType, TargetKind } from './event-types';

function sanitizeError(error: unknown) {
	const message = error instanceof Error ? error.message : String(error);
	return message.slice(0, 500);
}

type OperationTarget = { targetKind: TargetKind; targetId: string | null };

/**
 * Records the outcome of a risky external step (email delivery, ...) against one durable
 * row per operation instance (operation_type + idempotency_key). A failure upserts/updates
 * that row so it surfaces on the Operations screen; a success clears an existing failure row
 * back to 'succeeded' instead of leaving it stuck. Nothing is written on a first-try success,
 * since there is nothing to recover. When actorEmail is supplied, the failure is also logged
 * to the owner audit trail under the same correlation id.
 */
export async function recordOperationOutcome(
	client: SupabaseClient<Database>,
	params: {
		operationType: OperationType;
		idempotencyKey: string;
		target: OperationTarget;
		actorEmail?: string;
	} & ({ success: true } | { success: false; error: unknown })
) {
	const { operationType, idempotencyKey, target } = params;

	if (params.success) {
		const { error } = await client
			.from('platform_operation_attempts')
			.update({ status: 'succeeded', last_error: null })
			.eq('operation_type', operationType)
			.eq('idempotency_key', idempotencyKey)
			.neq('status', 'succeeded');
		if (error) throw error;
		return;
	}

	const sanitized = sanitizeError(params.error);
	const { data: existing, error: lookupError } = await client
		.from('platform_operation_attempts')
		.select('id, attempt_count, correlation_id')
		.eq('operation_type', operationType)
		.eq('idempotency_key', idempotencyKey)
		.maybeSingle();
	if (lookupError) throw lookupError;

	let correlationId: string;
	if (existing) {
		const { error } = await client
			.from('platform_operation_attempts')
			.update({
				status: 'retrying',
				attempt_count: existing.attempt_count + 1,
				last_error: sanitized
			})
			.eq('id', existing.id);
		if (error) throw error;
		correlationId = existing.correlation_id;
	} else {
		const { data: inserted, error } = await client
			.from('platform_operation_attempts')
			.insert({
				operation_type: operationType,
				idempotency_key: idempotencyKey,
				target_kind: target.targetKind,
				target_id: target.targetId,
				status: 'retrying',
				attempt_count: 1,
				last_error: sanitized
			})
			.select('correlation_id')
			.single();
		if (error) throw error;
		correlationId = inserted.correlation_id;
	}

	if (params.actorEmail) {
		const { error } = await client.from('platform_owner_audit_events').insert({
			correlation_id: correlationId,
			actor_owner_email: params.actorEmail,
			event_type: `${operationType}.failed`,
			target_type: target.targetKind,
			target_key: target.targetId,
			after_state: { error: sanitized }
		});
		if (error) throw error;
	}
}

export async function createOwnerNotification(
	client: SupabaseClient<Database>,
	params: {
		kind: string;
		severity: 'info' | 'attention' | 'urgent';
		title: string;
		body?: string;
		target: { targetKind: NotificationTargetKind; targetId: string | null };
		correlationId?: string;
	}
) {
	const { error } = await client.from('platform_owner_notifications').insert({
		kind: params.kind,
		severity: params.severity,
		title: params.title,
		body: params.body ?? null,
		target_kind: params.target.targetKind,
		target_id: params.target.targetId,
		correlation_id: params.correlationId ?? null
	});
	if (error) throw error;
}
