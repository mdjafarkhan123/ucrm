import { fetchTwilioUsageRecords, TwilioProvisioningError } from './twilio';
import type { SmsUsageReconciliationStore } from './sms-usage-reconciliation-store';
import { defaultResolveSmsCredentials, type ResolveSmsCredentials } from './sms-worker';

export type SmsUsageReconciliationResult = {
	organizationsChecked: number;
	daysChecked: number;
	matched: number;
	drifted: number;
	failed: number;
};

// All outbound SMS Twilio actually billed -- excludes inbound, which we never charge a contractor for, so it
// would manufacture false drift if included (see this stage's migration header for the researched category
// list).
const USAGE_CATEGORY = 'sms-outbound';

function addDays(dateOnly: string, days: number): string {
	const date = new Date(`${dateOnly}T00:00:00Z`);
	date.setUTCDate(date.getUTCDate() + days);
	return date.toISOString().slice(0, 10);
}

/**
 * Stage 8 part 2: the account-level cross-check price reconciliation (8-1) cannot do, since 8-1 can only ever
 * verify a message our own system already knows about. This compares Twilio's own daily Usage Records against
 * our settled totals for the same organization/day, day by day across each candidate's bounded window, and
 * records one finding per day -- mirroring runSmsPriceReconciliationCron's per-item isolation so one
 * organization's failure never aborts the sweep or corrupts another organization's cursor.
 */
export async function runSmsUsageReconciliationCron(
	store: SmsUsageReconciliationStore,
	dependencies: {
		resolveCredentials?: ResolveSmsCredentials;
		fetchUsageRecords?: typeof fetchTwilioUsageRecords;
	} = {}
): Promise<SmsUsageReconciliationResult> {
	const resolveCredentials = dependencies.resolveCredentials ?? defaultResolveSmsCredentials;
	const fetchUsageRecords = dependencies.fetchUsageRecords ?? fetchTwilioUsageRecords;

	const candidates = await store.listCandidates(50);
	const result: SmsUsageReconciliationResult = {
		organizationsChecked: 0,
		daysChecked: 0,
		matched: 0,
		drifted: 0,
		failed: 0
	};

	for (const candidate of candidates) {
		result.organizationsChecked += 1;
		try {
			const credentials = await resolveCredentials({
				organizationId: candidate.organizationId,
				twilioAccountId: candidate.twilioAccountId,
				subaccountSid: candidate.subaccountSid
			});

			const [providerRecords, ourTotals] = await Promise.all([
				fetchUsageRecords({
					subaccountSid: candidate.subaccountSid,
					category: USAGE_CATEGORY,
					startDate: candidate.windowStart,
					endDate: candidate.windowEnd,
					apiKeySid: credentials.apiKeySid,
					apiKeySecret: credentials.apiKeySecret
				}),
				store.getOurTotals({
					organizationId: candidate.organizationId,
					windowStart: candidate.windowStart,
					windowEnd: candidate.windowEnd
				})
			]);

			const providerByDate = new Map(providerRecords.map((record) => [record.usageDate, record]));
			const ourByDate = new Map(ourTotals.map((total) => [total.usageDate, total]));
			const priceCurrency =
				providerRecords[0]?.priceCurrency ??
				ourTotals.find((total) => total.priceCurrency)?.priceCurrency ??
				'USD';

			for (let date = candidate.windowStart; date <= candidate.windowEnd; date = addDays(date, 1)) {
				const provider = providerByDate.get(date);
				const ours = ourByDate.get(date);
				const ourMessageCount = ours?.messageCount ?? 0;
				const ourPriceMinor = ours?.priceMinor ?? 0;
				const providerMessageCount = provider?.messageCount ?? 0;
				const providerPriceMinor = provider?.priceMinor ?? 0;

				await store.recordFinding({
					organizationId: candidate.organizationId,
					usageDate: date,
					ourMessageCount,
					ourPriceMinor,
					providerMessageCount,
					providerPriceMinor,
					priceCurrency
				});

				result.daysChecked += 1;
				if (ourMessageCount !== providerMessageCount || ourPriceMinor !== providerPriceMinor) {
					result.drifted += 1;
				} else {
					result.matched += 1;
				}
			}

			await store.advanceCursor({
				organizationId: candidate.organizationId,
				reconciledThrough: candidate.windowEnd
			});
		} catch (error) {
			result.failed += 1;
			const message =
				error instanceof TwilioProvisioningError
					? error.message
					: error instanceof Error
						? error.message
						: 'Unknown error.';
			console.error('SMS usage-window reconciliation failed for one organization.', {
				organizationId: candidate.organizationId,
				error: message
			});
			// No cursor write on failure -- listCandidates orders oldest-checked-first, so this organization is
			// simply retried on the next run instead of needing its own backoff schedule.
		}
	}

	return result;
}
