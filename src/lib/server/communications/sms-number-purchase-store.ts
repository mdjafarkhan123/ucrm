import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import type { AddressRequirement, NumberType } from './twilio-country-catalog';

// The durable-state boundary for the number purchase saga (Stage 10 Part 2). Every transition is one database
// function from 20261222120000_sms_number_purchase.sql, so the money hold, the charge and the order state always
// move together. The saga depends on this port; tests drive it against an in-memory fake.

export type NumberOrderState = 'reserved' | 'purchasing' | 'purchased' | 'completed' | 'failed';

export type NumberOrder = {
	id: string;
	organizationId: string;
	phoneNumber: string;
	countryCode: string;
	numberType: NumberType;
	capabilities: { sms: boolean; mms: boolean; voice: boolean };
	locality: string | null;
	region: string | null;
	addressRequirement: AddressRequirement;
	bundleSid: string | null;
	addressSid: string | null;
	currencyCode: string;
	monthlyMinor: number;
	setupMinor: number;
	chargeMinor: number;
	state: NumberOrderState;
	providerPhoneNumberSid: string | null;
	senderIdentityId: string | null;
	failureCode: string | null;
	createdAt: string;
	updatedAt: string;
	purchasedAt: string | null;
};

export type OpenNumberOrderInput = {
	organizationId: string;
	actorId: string;
	idempotencyKey: string;
	phoneNumber: string;
	countryCode: string;
	numberType: NumberType;
	capabilities: { sms: boolean; mms: boolean; voice: boolean };
	locality: string | null;
	region: string | null;
	addressRequirement: AddressRequirement;
	bundleSid: string | null;
	addressSid: string | null;
};

/** A refusal the database raised on purpose (the function's P0001 message is the code). */
export class NumberOrderRefusedError extends Error {
	constructor(public readonly code: string) {
		super(code);
		this.name = 'NumberOrderRefusedError';
	}
}

export class NumberOrderStoreError extends Error {
	constructor(message: string) {
		super(message);
		this.name = 'NumberOrderStoreError';
	}
}

export type NumberPurchaseStore = {
	findOrderByKey(organizationId: string, idempotencyKey: string): Promise<NumberOrder | null>;
	getOrder(organizationId: string, orderId: string): Promise<NumberOrder | null>;
	/** True when Uplift or the package has switched texting off for this business. */
	isTextingSwitchedOff(organizationId: string): Promise<boolean>;
	openOrder(input: OpenNumberOrderInput): Promise<NumberOrder>;
	/** Move a reserved order to purchasing. True only for the one caller that won it. */
	claimPurchase(orderId: string): Promise<boolean>;
	/** Let a retry take over an order stuck purchasing since before `staleBefore`. True only for one caller. */
	reclaimPurchase(orderId: string, staleBefore: Date): Promise<boolean>;
	recordPurchased(orderId: string, providerPhoneNumberSid: string): Promise<NumberOrder>;
	failOrder(orderId: string, failureCode: string): Promise<NumberOrder>;
	completeOrder(orderId: string): Promise<NumberOrder>;
};

type OrderRow = Database['public']['Tables']['communication_sms_number_orders']['Row'];

const ORDER_COLUMNS =
	'id, organization_id, phone_number, country_code, number_type, capable_sms, capable_mms, capable_voice, locality, region, address_requirement, bundle_sid, address_sid, currency_code, monthly_minor, setup_minor, charge_minor, state, provider_phone_number_sid, sender_identity_id, failure_code, created_at, updated_at, purchased_at';

function toOrder(row: Pick<OrderRow, keyof OrderRow>): NumberOrder {
	return {
		id: row.id,
		organizationId: row.organization_id,
		phoneNumber: row.phone_number,
		countryCode: row.country_code,
		numberType: row.number_type as NumberType,
		capabilities: { sms: row.capable_sms, mms: row.capable_mms, voice: row.capable_voice },
		locality: row.locality,
		region: row.region,
		addressRequirement: row.address_requirement as AddressRequirement,
		bundleSid: row.bundle_sid,
		addressSid: row.address_sid,
		currencyCode: row.currency_code,
		monthlyMinor: Number(row.monthly_minor),
		setupMinor: Number(row.setup_minor),
		chargeMinor: Number(row.charge_minor),
		state: row.state as NumberOrderState,
		providerPhoneNumberSid: row.provider_phone_number_sid,
		senderIdentityId: row.sender_identity_id,
		failureCode: row.failure_code,
		createdAt: row.created_at,
		updatedAt: row.updated_at,
		purchasedAt: row.purchased_at
	};
}

function rpcFailure(error: { code?: string; message: string }, fallback: string): Error {
	if (error.code === 'P0001') return new NumberOrderRefusedError(error.message);
	return new NumberOrderStoreError(fallback);
}

export function createSupabaseNumberPurchaseStore(
	client: SupabaseClient<Database>
): NumberPurchaseStore {
	return {
		async findOrderByKey(organizationId, idempotencyKey) {
			const { data, error } = await client
				.from('communication_sms_number_orders')
				.select(ORDER_COLUMNS)
				.eq('organization_id', organizationId)
				.eq('idempotency_key', idempotencyKey)
				.maybeSingle();
			if (error) throw new NumberOrderStoreError('Could not load the number order.');
			return data ? toOrder(data as OrderRow) : null;
		},

		async getOrder(organizationId, orderId) {
			const { data, error } = await client
				.from('communication_sms_number_orders')
				.select(ORDER_COLUMNS)
				.eq('organization_id', organizationId)
				.eq('id', orderId)
				.maybeSingle();
			if (error) throw new NumberOrderStoreError('Could not load the number order.');
			return data ? toOrder(data as OrderRow) : null;
		},

		async isTextingSwitchedOff(organizationId) {
			const { data, error } = await client
				.from('communication_sms_org_modes')
				.select('package_max_mode, override_mode')
				.eq('organization_id', organizationId)
				.maybeSingle();
			if (error) throw new NumberOrderStoreError('Could not load the texting mode.');
			if (!data) return false;
			if (data.override_mode) return data.override_mode === 'off';
			return data.package_max_mode === 'off';
		},

		async openOrder(input) {
			const { data, error } = await client.rpc('communication_sms_open_number_order', {
				p_organization_id: input.organizationId,
				p_actor: input.actorId,
				p_idempotency_key: input.idempotencyKey,
				p_phone_number: input.phoneNumber,
				p_country_code: input.countryCode,
				p_number_type: input.numberType,
				p_capable_sms: input.capabilities.sms,
				p_capable_mms: input.capabilities.mms,
				p_capable_voice: input.capabilities.voice,
				p_locality: input.locality ?? undefined,
				p_region: input.region ?? undefined,
				p_address_requirement: input.addressRequirement,
				p_bundle_sid: input.bundleSid ?? undefined,
				p_address_sid: input.addressSid ?? undefined
			});
			if (error) throw rpcFailure(error, 'Could not open the number order.');
			return toOrder(data as OrderRow);
		},

		async claimPurchase(orderId) {
			const { data, error } = await client.rpc('communication_sms_claim_number_order_purchase', {
				p_order_id: orderId
			});
			if (error) throw rpcFailure(error, 'Could not update the number order.');
			return data === true;
		},

		async reclaimPurchase(orderId, staleBefore) {
			const { data, error } = await client.rpc('communication_sms_reclaim_number_order_purchase', {
				p_order_id: orderId,
				p_stale_before: staleBefore.toISOString()
			});
			if (error) throw rpcFailure(error, 'Could not update the number order.');
			return data === true;
		},

		async recordPurchased(orderId, providerPhoneNumberSid) {
			const { data, error } = await client.rpc('communication_sms_record_number_purchased', {
				p_order_id: orderId,
				p_provider_phone_number_sid: providerPhoneNumberSid
			});
			if (error) throw rpcFailure(error, 'Could not record the bought number.');
			return toOrder(data as OrderRow);
		},

		async failOrder(orderId, failureCode) {
			const { data, error } = await client.rpc('communication_sms_fail_number_order', {
				p_order_id: orderId,
				p_failure_code: failureCode
			});
			if (error) throw rpcFailure(error, 'Could not close the number order.');
			return toOrder(data as OrderRow);
		},

		async completeOrder(orderId) {
			const { data, error } = await client.rpc('communication_sms_complete_number_order', {
				p_order_id: orderId
			});
			if (error) throw rpcFailure(error, 'Could not finish the number order.');
			return toOrder(data as OrderRow);
		}
	};
}
