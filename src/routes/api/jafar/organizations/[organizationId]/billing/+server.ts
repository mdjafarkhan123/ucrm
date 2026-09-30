import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	billingStepUpActions,
	organizationBillingCommandSchema,
	zodOwnerFieldErrors,
	type OrganizationBillingCommand
} from '$lib/server/validation/owner.schema';

// Package builder P4b: the Billing workspace reads the organization's offsite billing ledger in one call
// and runs one ledger command per POST (ADR 0003 decision 6). P8b adds changing the package, cancelling a
// scheduled change, and using the credit a change returns. The ledger rows themselves record who acted
// and why, so there is no separate audit write here.

function dollars(cents: number) {
	return `$${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

// The database names amounts in cents; Jafar reads dollars.
function readableDatabaseMessage(message: string) {
	return message.replace(/(\d+) cents/g, (_match, cents: string) => dollars(Number(cents)));
}

async function loadBilling(organizationId: string) {
	const { data, error } = await getOwnerSupabaseClient().rpc('owner_organization_billing', {
		target_organization_id: organizationId
	});
	if (error) throw error;
	return data;
}

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	try {
		const billing = await loadBilling(parsedId.data);
		if (!billing) return json({ error: 'Organization was not found.' }, { status: 404 });
		return json({ billing }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not load organization billing.', error);
		return json({ error: 'Billing could not be loaded.' }, { status: 500 });
	}
};

function runCommand(organizationId: string, email: string, command: OrganizationBillingCommand) {
	const client = getOwnerSupabaseClient();
	const common = {
		target_organization_id: organizationId,
		actor_owner_email: email,
		idempotency_key: command.idempotency_key
	};
	switch (command.action) {
		case 'add_charge':
			return client.rpc('add_organization_billing_charge', {
				...common,
				period_start: command.period_start ?? undefined
			});
		case 'record_payment':
			return client.rpc('record_organization_billing_receipt', {
				...common,
				received_on: command.received_on,
				amount_usd_cents: command.amount_usd_cents,
				method: command.method,
				private_reference: command.private_reference,
				note: command.note ?? undefined,
				applications: command.applications
			});
		case 'apply_credit':
			return client.rpc('apply_organization_billing_credit', {
				...common,
				receipt_id: command.receipt_id,
				charge_id: command.charge_id,
				amount_usd_cents: command.amount_usd_cents
			});
		case 'refund':
			return client.rpc('record_organization_billing_refund', {
				...common,
				receipt_id: command.receipt_id,
				refunded_on: command.refunded_on,
				amount_usd_cents: command.amount_usd_cents,
				method: command.method,
				reason: command.reason,
				private_reference: command.private_reference ?? undefined
			});
		case 'void':
			return client.rpc('void_organization_billing_record', {
				...common,
				record_kind: command.record_kind,
				record_id: command.record_id,
				reason: command.reason
			});
		case 'correct_payment':
			return client.rpc('correct_organization_billing_receipt', {
				...common,
				original_receipt_id: command.original_receipt_id,
				received_on: command.received_on,
				amount_usd_cents: command.amount_usd_cents,
				method: command.method,
				private_reference: command.private_reference,
				reason: command.reason,
				note: command.note ?? undefined
			});
		case 'confirm_coverage':
			return client.rpc('confirm_organization_billing_coverage', {
				...common,
				charge_id: command.charge_id,
				covered_from: command.covered_from,
				covered_through: command.covered_through
			});
		case 'adjust_paid_through':
			return client.rpc('adjust_organization_paid_through', {
				...common,
				paid_through_date: command.paid_through_date,
				reason: command.reason
			});
		case 'grant_free_access':
			return client.rpc('grant_organization_free_access', {
				...common,
				starts_on: command.starts_on,
				ends_on: command.ends_on,
				reason: command.reason
			});
		case 'extend_free_access':
			return client.rpc('extend_organization_free_access', {
				...common,
				grant_id: command.grant_id,
				ends_on: command.ends_on,
				reason: command.reason
			});
		case 'end_free_access':
			return client.rpc('end_organization_free_access', {
				...common,
				grant_id: command.grant_id,
				reason: command.reason
			});
		case 'change_package':
			return client.rpc('change_organization_package', {
				...common,
				target_edition_id: command.edition_id,
				billing_interval: command.billing_interval,
				timing: command.timing,
				expected_effective_date: command.expected_effective_date,
				expected_credit_usd_cents: command.expected_credit_usd_cents,
				expected_charge_usd_cents: command.expected_charge_usd_cents,
				reason: command.reason
			});
		case 'cancel_package_change':
			return client.rpc('cancel_scheduled_package_change', {
				...common,
				agreement_id: command.agreement_id,
				reason: command.reason
			});
		case 'apply_change_credit':
			return client.rpc('apply_organization_billing_credit_note', {
				...common,
				credit_note_id: command.credit_note_id,
				charge_id: command.charge_id,
				amount_usd_cents: command.amount_usd_cents
			});
	}
}

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = organizationBillingCommandSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the billing details.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	if (billingStepUpActions.has(parsed.data.action) && !consumeOwnerStepUp(event, session)) {
		return json(
			{
				error: 'Confirm your password before changing recorded money or dates.',
				step_up_required: true
			},
			{ status: 403 }
		);
	}

	try {
		const { data: organization, error: organizationError } = await getOwnerSupabaseClient()
			.from('organizations')
			.select('id')
			.eq('id', parsedId.data)
			.maybeSingle();
		if (organizationError) throw organizationError;
		if (!organization) return json({ error: 'Organization was not found.' }, { status: 404 });

		const result = await runCommand(parsedId.data, session.email, parsed.data);
		if (result.error) {
			if (result.error.code === 'P0409') {
				// A package change is refused when its date or amounts moved after Jafar reviewed them; the
				// dialog then shows the fresh preview.
				if (parsed.data.action === 'change_package')
					return json(
						{
							error: 'The change moved on since you reviewed it. Check the new figures below.',
							preview_stale: true
						},
						{ status: 409 }
					);
				return json(
					{ error: 'This charge changed while you were looking at it. Review it and try again.' },
					{ status: 409 }
				);
			}
			if (['23503', '23505', '23514'].includes(result.error.code)) {
				return json({ error: readableDatabaseMessage(result.error.message) }, { status: 409 });
			}
			throw result.error;
		}

		const billing = await loadBilling(parsedId.data);
		return json({ command: result.data, billing }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not record the billing action.', error);
		return json({ error: 'The billing action could not be recorded.' }, { status: 500 });
	}
};
