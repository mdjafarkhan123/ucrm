import { httpError } from '$lib/http-error';
import { countryDisplayName } from '$lib/settings/country-names';
import { formatMinor } from '$lib/communications/sms-number-shop';

// Whether each texting number can text yet (Stage 10 Part 4). Owning a number, its paperwork and its texting
// approval are separate facts (docs/global-sms-behavior-contract.md § Part 4), so the server sends each fact as
// it is and this pure module turns them into the card the Phone & SMS page draws: four steps (Bought,
// Paperwork, Approval, Texting), one status with the single next action, and the countries the business can
// text. Pure, so the same rules are unit-tested without a browser or a database.

export type ReadinessOrder = {
	state: 'reserved' | 'purchasing' | 'purchased' | 'completed' | 'failed';
	purchased_at: string | null;
	created_at: string;
	/** The number was bought with paperwork (a bundle) or a registered address. */
	needs_paperwork: boolean;
};

export type ReadinessPaperwork = {
	id: string;
	status: 'draft' | 'sending' | 'under_review' | 'approved' | 'needs_fix';
	failure_reason: string | null;
	valid_until: string | null;
	submitted_at: string | null;
	decided_at: string | null;
};

/** A toll-free number's own carrier check (Twilio Toll-Free Verification). */
export type ReadinessTollFreeCheck = {
	id: string;
	status: 'draft' | 'sending' | 'under_review' | 'approved' | 'needs_fix';
	failure_reason: string | null;
	submitted_at: string | null;
	decided_at: string | null;
	edit_expires_at: string | null;
};

export type ReadinessRegistration = {
	status: 'waiting_for_info' | 'under_review' | 'action_needed' | 'approved';
	required_fixes: string | null;
	submitted_at: string | null;
	updated_at: string;
};

/**
 * The number's monthly renewal (Part 7): the month it renews next (or the overdue one), its price on that day,
 * and whether that month is paid. A released number keeps its card for a while so the business sees what
 * happened.
 */
export type ReadinessRenewal = {
	state: 'paid' | 'unpaid' | 'released';
	renews_at: string;
	/** The number price on the renewal day; null while Uplift has no price for this country and kind. */
	price_minor: number | null;
	currency: string;
	unpaid_since: string | null;
	grace_ends_at: string | null;
	released_at: string | null;
};

/** What the bought texting balance has free to spend (settled minus held). */
export type ReadinessBalance = { available_minor: number; currency: string };

export type ReadinessNumber = {
	/** The sender's id once it exists; an order still being connected has none yet. */
	sender_id: string | null;
	order_id: string | null;
	phone_number: string;
	display_name: string | null;
	country_code: string;
	sender_type: 'long_code' | 'toll_free' | 'short_code' | 'alphanumeric';
	number_type: 'local' | 'mobile' | 'national' | 'toll_free' | null;
	lifecycle_state: 'pending_setup' | 'ready' | 'restricted' | 'suspended' | 'released' | null;
	capabilities: { sms: boolean; mms: boolean; voice: boolean };
	is_default_sender: boolean;
	created_at: string;
	order: ReadinessOrder | null;
	paperwork: ReadinessPaperwork | null;
	toll_free_check: ReadinessTollFreeCheck | null;
	/** Absent while the number is still being connected. */
	renewal?: ReadinessRenewal | null;
};

export type ReadinessHome = {
	numbers: ReadinessNumber[];
	balance?: ReadinessBalance | null;
	/** The business's US texting registration (A2P 10DLC), which every US local number shares. */
	us_registration: ReadinessRegistration | null;
};

export type StepKey = 'bought' | 'paperwork' | 'approval' | 'texting';
export type StepState =
	'done' | 'waiting' | 'connecting' | 'your_turn' | 'failed' | 'paused' | 'ended' | 'not_yet';
export type ReadinessStep = { key: StepKey; label: string; state: StepState; hint: string };

export type ReadinessStatus =
	| 'getting_ready'
	| 'texting_paused'
	| 'sending_paused'
	| 'released'
	| 'action_needed'
	| 'business_details_needed'
	| 'under_review'
	| 'ready_to_text';

export type ReadinessAction =
	| { kind: 'add_business_details'; label: string }
	| { kind: 'fix_business_details'; label: string }
	| { kind: 'see_business_details'; label: string }
	| { kind: 'toll_free_check'; label: string; sender_id: string }
	| { kind: 'update_paperwork'; label: string; paperwork_id: string }
	| { kind: 'see_paperwork'; label: string; paperwork_id: string }
	| { kind: 'add_number'; label: string };

/**
 * The renewal strip between a card's steps and its band (board `QiDBX`). The meter shows how much of the price
 * the balance covers; after a failed renewal it becomes a 14-day countdown to release.
 */
export type RenewalStrip = {
	tone: 'paid' | 'short' | 'unpaid' | 'released';
	eyebrow: string;
	headline: string;
	/** Released only: the quiet line under the date. */
	note: string | null;
	meter:
		| { kind: 'balance'; left: string; right: string; fraction: number }
		| { kind: 'days'; left: string; right: string; days_left: number; total: number }
		| null;
	/** Add money's amount words, when the strip offers it. */
	add_money: boolean;
};

export type NumberCard = {
	key: string;
	sender_id: string | null;
	name: string;
	/** The name the business gave the number, if any; `name` falls back to the number itself. */
	display_name: string | null;
	/** "+44 7700 900412 · United Kingdom · Mobile", with no repeated number when it has no name. */
	detail: string;
	country_code: string;
	is_default: boolean;
	can_be_default: boolean;
	can_text: boolean;
	steps: ReadinessStep[];
	status: ReadinessStatus | null;
	title: string;
	line: string;
	action: ReadinessAction | null;
	capabilities: { sms: boolean; mms: boolean; voice: boolean };
	renewal: RenewalStrip | null;
	released: boolean;
};

export type CountryReach = { code: string; name: string; ready: boolean };

export type ReadinessSummary = {
	total: number;
	can_text: number;
	needs_you: string[];
	/** The band line of the one number still on its way, when only one is. */
	only_waiting_line: string | null;
	counts: Partial<Record<ReadinessStatus, number>>;
	countries: CountryReach[];
};

export const STATUS_LABELS: Record<ReadinessStatus, string> = {
	ready_to_text: 'Ready to text',
	action_needed: 'Action needed',
	business_details_needed: 'Business details needed',
	under_review: 'Under review',
	getting_ready: 'Getting your number ready',
	texting_paused: 'Texting paused',
	sending_paused: 'Sending paused',
	released: 'Released'
};

/** The order the summary's bar and legend list statuses in. */
export const STATUS_ORDER: ReadinessStatus[] = [
	'ready_to_text',
	'sending_paused',
	'texting_paused',
	'action_needed',
	'business_details_needed',
	'under_review',
	'getting_ready',
	'released'
];

const NUMBER_TYPE_LABELS: Record<NonNullable<ReadinessNumber['number_type']>, string> = {
	local: 'Local',
	mobile: 'Mobile',
	national: 'National',
	toll_free: 'Toll-free'
};

/** US and Canadian toll-free numbers share one North American range and text both countries. */
const TOLL_FREE_COUNTRIES = ['US', 'CA'];

function shortDate(iso: string | null) {
	if (!iso) return '';
	return new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

function isTollFree(number: ReadinessNumber) {
	return number.sender_type === 'toll_free' || number.number_type === 'toll_free';
}

/** The countries a number texts once it is ready: its own, or both for a North American toll-free number. */
export function numberCountries(number: ReadinessNumber): string[] {
	return isTollFree(number) && TOLL_FREE_COUNTRIES.includes(number.country_code)
		? TOLL_FREE_COUNTRIES
		: [number.country_code];
}

function countryPhrase(number: ReadinessNumber) {
	return isTollFree(number) && TOLL_FREE_COUNTRIES.includes(number.country_code)
		? 'US and Canada'
		: countryDisplayName(number.country_code);
}

/** Which texting approval a number needs before it can text its own country. */
type Approval = 'none' | 'us_registration' | 'toll_free_check';

function approvalFor(number: ReadinessNumber): Approval {
	if (isTollFree(number)) return 'toll_free_check';
	// A US local number texting US customers needs the business's US registration. A Canadian local number
	// texting Canadians does not (texting the US from it is a destination request, Part 5).
	if (number.sender_type === 'long_code' && number.country_code === 'US') return 'us_registration';
	return 'none';
}

function displayNumber(phone: string) {
	const nanp = /^\+1(\d{3})(\d{3})(\d{4})$/.exec(phone);
	if (nanp) return `+1 ${nanp[1]}-${nanp[2]}-${nanp[3]}`;
	const uk = /^\+44(\d{4})(\d{6})$/.exec(phone);
	if (uk) return `+44 ${uk[1]} ${uk[2]}`;
	return phone;
}

function paperworkLapsed(paperwork: ReadinessPaperwork, now: Date) {
	return (
		paperwork.valid_until !== null && new Date(paperwork.valid_until).getTime() <= now.getTime()
	);
}

function connecting(number: ReadinessNumber) {
	return (
		number.sender_id === null ||
		(number.order !== null && number.order.state !== 'completed' && number.order.state !== 'failed')
	);
}

function boughtStep(number: ReadinessNumber): ReadinessStep {
	if (connecting(number))
		return { key: 'bought', label: 'Bought', state: 'connecting', hint: 'Connecting' };
	return {
		key: 'bought',
		label: 'Bought',
		state: 'done',
		hint: shortDate(number.order?.purchased_at ?? number.created_at)
	};
}

function paperworkStep(number: ReadinessNumber, now: Date): ReadinessStep {
	const step = { key: 'paperwork' as const, label: 'Paperwork' };
	if (connecting(number)) {
		return number.order?.needs_paperwork
			? { ...step, state: 'not_yet', hint: 'Not yet' }
			: { ...step, state: 'not_yet', hint: 'Not needed' };
	}
	const paperwork = number.paperwork;
	if (!number.order?.needs_paperwork || !paperwork) {
		return { ...step, state: 'done', hint: 'Not needed' };
	}
	if (paperwork.status === 'needs_fix') return { ...step, state: 'failed', hint: 'Needs update' };
	if (paperworkLapsed(paperwork, now)) return { ...step, state: 'failed', hint: 'Date passed' };
	if (paperwork.status === 'approved')
		return { ...step, state: 'done', hint: shortDate(paperwork.decided_at) || 'Approved' };
	return { ...step, state: 'waiting', hint: 'Under review' };
}

function approvalStep(
	number: ReadinessNumber,
	registration: ReadinessRegistration | null
): ReadinessStep {
	const step = { key: 'approval' as const, label: 'Approval' };
	const approval = approvalFor(number);
	if (approval === 'none' || number.lifecycle_state === 'ready')
		return approval === 'none'
			? { ...step, state: connecting(number) ? 'not_yet' : 'done', hint: 'Not needed' }
			: { ...step, state: 'done', hint: 'Approved' };
	if (connecting(number)) return { ...step, state: 'not_yet', hint: 'Not yet' };
	if (approval === 'toll_free_check') {
		const check = number.toll_free_check;
		switch (check?.status) {
			case 'sending':
			case 'under_review':
				return { ...step, state: 'waiting', hint: `Sent ${shortDate(check.submitted_at)}` };
			case 'needs_fix':
				return { ...step, state: 'failed', hint: 'Turned down' };
			case 'approved':
				return { ...step, state: 'done', hint: 'Approved' };
			default:
				return { ...step, state: 'your_turn', hint: 'Your turn' };
		}
	}
	switch (registration?.status) {
		case 'under_review':
			return { ...step, state: 'waiting', hint: `Sent ${shortDate(registration.submitted_at)}` };
		case 'action_needed':
			return { ...step, state: 'failed', hint: 'Turned down' };
		case 'approved':
			return { ...step, state: 'done', hint: 'Approved' };
		default:
			return { ...step, state: 'your_turn', hint: 'Your turn' };
	}
}

function textingStep(number: ReadinessNumber): ReadinessStep {
	const step = { key: 'texting' as const, label: 'Texting' };
	if (number.lifecycle_state === 'released' || number.renewal?.state === 'released')
		return { ...step, state: 'ended', hint: 'Ended' };
	if (number.renewal?.state === 'unpaid' && number.lifecycle_state === 'ready')
		return { ...step, state: 'paused', hint: 'Paused' };
	if (number.lifecycle_state === 'ready' && number.capabilities.sms)
		return { ...step, state: 'done', hint: countryPhrase(number) };
	if (number.lifecycle_state === 'restricted' || number.lifecycle_state === 'suspended')
		return { ...step, state: 'failed', hint: 'Paused' };
	return { ...step, state: 'not_yet', hint: 'Not yet' };
}

function band(
	number: ReadinessNumber,
	steps: Record<StepKey, ReadinessStep>,
	now: Date
): Pick<NumberCard, 'status' | 'title' | 'line' | 'action'> {
	const country = countryDisplayName(number.country_code);
	const paperwork = number.paperwork;
	const paperworkFix =
		paperwork && steps.paperwork.state === 'failed'
			? ({
					kind: 'update_paperwork',
					label: 'Update paperwork',
					paperwork_id: paperwork.id
				} as const)
			: null;

	if (steps.texting.state === 'ended') {
		return {
			status: 'released',
			title: 'Number released',
			line: 'Add a number to text again.',
			action: { kind: 'add_number', label: 'Add number' }
		};
	}
	if (steps.texting.state === 'paused') {
		return {
			status: 'sending_paused',
			title: 'Sending paused',
			line: 'Replies still arrive. Sending starts again as soon as the renewal is paid.',
			action: null
		};
	}
	if (steps.bought.state === 'connecting') {
		return {
			status: 'getting_ready',
			title: 'Getting your number ready',
			line: 'This takes about a minute. You can leave this page; it carries on.',
			action: null
		};
	}
	if (steps.texting.state === 'failed') {
		const lapsed = paperwork !== null && paperworkLapsed(paperwork, now);
		return {
			status: 'texting_paused',
			title: lapsed ? `Texting paused: ${country} paperwork date passed` : 'Texting paused',
			line: paperworkFix
				? `${paperwork?.failure_reason ?? 'Update your paperwork'} and we'll switch texting back on. Calls still work.`
				: 'Carriers paused texting on this number. Contact us and we will help. Calls still work.',
			action: paperworkFix
		};
	}
	if (paperworkFix) {
		const by = paperwork?.valid_until ? ` Add it by ${shortDate(paperwork.valid_until)}` : '';
		return {
			status: 'action_needed',
			title: `${country} paperwork needs an update`,
			line: `${paperwork?.failure_reason ?? 'The phone company asked for a change.'}${by ? `${by} so this number keeps texting.` : ''}`,
			action: paperworkFix
		};
	}
	if (steps.approval.state === 'failed' && approvalFor(number) === 'toll_free_check') {
		const check = number.toll_free_check;
		const by = check?.edit_expires_at
			? ` Send the fix by ${shortDate(check.edit_expires_at)}.`
			: '';
		return {
			status: 'action_needed',
			title: 'Carriers turned down your toll-free check',
			line: `${check?.failure_reason ?? 'Carriers asked for a change.'}${by}`,
			action: number.sender_id
				? { kind: 'toll_free_check', label: 'Fix and send again', sender_id: number.sender_id }
				: null
		};
	}
	if (steps.approval.state === 'failed') {
		return {
			status: 'action_needed',
			title: 'Carriers turned down your US texting registration',
			line: "Fix what they asked for and we'll send it again.",
			action: { kind: 'fix_business_details', label: 'Fix and send again' }
		};
	}
	if (steps.texting.state === 'done') {
		return {
			status: 'ready_to_text',
			title: 'Ready to text',
			line: `Customers in ${countryPhrase(number)} get your texts from this number.`,
			action: null
		};
	}
	if (steps.approval.state === 'your_turn') {
		return approvalFor(number) === 'toll_free_check'
			? {
					status: 'business_details_needed',
					title: 'Business details needed',
					line: 'Toll-free numbers get a quick check before they text. Your business answers carry over.',
					action: number.sender_id
						? {
								kind: 'toll_free_check',
								label: 'Add business details',
								sender_id: number.sender_id
							}
						: null
				}
			: {
					status: 'business_details_needed',
					title: 'Business details needed',
					line: 'US numbers need a quick carrier check before they text.',
					action: { kind: 'add_business_details', label: 'Add business details' }
				};
	}
	if (steps.paperwork.state === 'waiting' && paperwork) {
		return {
			status: 'under_review',
			title: 'Under review',
			line: `Twilio is checking your ${country} paperwork. The answer shows here.`,
			action: { kind: 'see_paperwork', label: 'See what you sent', paperwork_id: paperwork.id }
		};
	}
	if (steps.approval.state === 'waiting' && approvalFor(number) === 'toll_free_check') {
		return {
			status: 'under_review',
			title: 'Under review',
			line: 'Carriers are checking your toll-free number, usually a few working days. The answer shows here.',
			action: number.sender_id
				? { kind: 'toll_free_check', label: 'See what you sent', sender_id: number.sender_id }
				: null
		};
	}
	if (steps.approval.state === 'waiting') {
		return {
			status: 'under_review',
			title: 'Under review',
			line: 'Carriers are checking your US texting registration, usually 3 to 7 working days. The answer shows here.',
			action: { kind: 'see_business_details', label: 'See what you sent' }
		};
	}
	if (!number.capabilities.sms) {
		return {
			status: null,
			title: '',
			line: '',
			action: null
		};
	}
	// Every gate has passed and Uplift is switching the number on.
	return {
		status: 'getting_ready',
		title: 'Getting your number ready',
		line: "Its approval came through. We're switching texting on for this number.",
		action: null
	};
}

const DAY_MS = 86_400_000;
const GRACE_DAYS = 14;

/** Whole days from now until a moment, counting a part day as a day. */
function daysUntil(iso: string, now: Date) {
	return Math.ceil((new Date(iso).getTime() - now.getTime()) / DAY_MS);
}

function renewsInWords(days: number) {
	if (days <= 0) return 'RENEWS TODAY';
	if (days === 1) return 'RENEWS TOMORROW';
	return `RENEWS IN ${days} DAYS`;
}

/** The renewal strip, or null for a number still being connected. */
export function renewalStrip(
	renewal: ReadinessRenewal | null | undefined,
	balance: ReadinessBalance | null | undefined,
	now = new Date()
): RenewalStrip | null {
	if (!renewal) return null;
	const money = (minor: number) => formatMinor(minor, renewal.currency);
	const available = Math.max(0, balance?.available_minor ?? 0);

	if (renewal.state === 'released') {
		return {
			tone: 'released',
			eyebrow: 'RELEASED',
			headline: `${shortDate(renewal.released_at)} · it no longer renews`,
			note: 'Your conversations are kept.',
			meter: null,
			add_money: false
		};
	}

	if (renewal.state === 'unpaid') {
		const daysLeft = renewal.grace_ends_at
			? Math.min(GRACE_DAYS, Math.max(0, daysUntil(renewal.grace_ends_at, now)))
			: 0;
		const short =
			renewal.price_minor === null ? null : Math.max(0, renewal.price_minor - available);
		return {
			tone: 'unpaid',
			eyebrow: `UNPAID SINCE ${shortDate(renewal.unpaid_since).toUpperCase()}`,
			headline: short ? `Add ${money(short)}` : 'Add money to renew',
			note: null,
			meter: {
				kind: 'days',
				left: `${daysLeft} of ${GRACE_DAYS} days left`,
				right: `released ${shortDate(renewal.grace_ends_at)}`,
				days_left: daysLeft,
				total: GRACE_DAYS
			},
			add_money: true
		};
	}

	const date = shortDate(renewal.renews_at);
	if (renewal.price_minor === null) {
		return {
			tone: 'paid',
			eyebrow: 'RENEWS',
			headline: date,
			note: null,
			meter: null,
			add_money: false
		};
	}
	const price = renewal.price_minor;
	const days = daysUntil(renewal.renews_at, now);
	if (available >= price) {
		return {
			tone: 'paid',
			eyebrow: 'RENEWS',
			headline: `${date} · ${money(price)}`,
			note: null,
			meter: {
				kind: 'balance',
				left: `Balance ${money(available)} covers it`,
				right: 'from your texting balance',
				fraction: 1
			},
			add_money: false
		};
	}
	// Short, but warnings start 3 days ahead (plan § Part 7); until then the strip stays calm.
	const soon = days <= 3;
	return {
		tone: soon ? 'short' : 'paid',
		eyebrow: soon ? renewsInWords(days) : 'RENEWS',
		headline: `${date} · ${money(price)}`,
		note: null,
		meter: {
			kind: 'balance',
			left: `${money(available)} of ${money(price)}`,
			right: `short by ${money(price - available)}`,
			fraction: price > 0 ? available / price : 1
		},
		add_money: true
	};
}

export function numberCard(
	number: ReadinessNumber,
	registration: ReadinessRegistration | null,
	now = new Date(),
	balance: ReadinessBalance | null = null
): NumberCard {
	const steps = {
		bought: boughtStep(number),
		paperwork: paperworkStep(number, now),
		approval: approvalStep(number, registration),
		texting: textingStep(number)
	};
	const typeLabel = number.number_type ? NUMBER_TYPE_LABELS[number.number_type] : null;
	const place = isTollFree(number) ? 'US and Canada' : countryDisplayName(number.country_code);
	const phone = displayNumber(number.phone_number);
	const name = number.display_name?.trim() || phone;
	const detail = [name === phone ? null : phone, place, typeLabel].filter(Boolean).join(' · ');
	const canText = steps.texting.state === 'done';
	const released = steps.texting.state === 'ended';
	return {
		key: number.sender_id ?? `order:${number.order_id ?? number.phone_number}`,
		sender_id: number.sender_id,
		name,
		display_name: number.display_name?.trim() || null,
		detail,
		country_code: number.country_code,
		is_default: number.is_default_sender && !released,
		can_be_default: canText && number.sender_id !== null,
		can_text: canText,
		steps: [steps.bought, steps.paperwork, steps.approval, steps.texting],
		capabilities: number.capabilities,
		renewal: renewalStrip(number.renewal, balance, now),
		released,
		...band(number, steps, now)
	};
}

const NEEDS_YOU: ReadinessStatus[] = [
	'action_needed',
	'business_details_needed',
	'texting_paused',
	'sending_paused'
];

/**
 * A country the business asked Uplift to switch on (Part 5c). It is Ready once Uplift has switched it on and
 * one of the business's numbers can text it; until then it shows Setting up.
 */
export type SummaryDestination = { country: string; status: 'setting_up' | 'ready' | 'off' };

/** A +1 number texts both the US and Canada once the country is switched on. */
const reachOf = (number: ReadinessNumber) =>
	TOLL_FREE_COUNTRIES.includes(number.country_code) ? TOLL_FREE_COUNTRIES : [number.country_code];

export function readinessSummary(
	allNumbers: ReadinessNumber[],
	allCards: NumberCard[],
	destinations: SummaryDestination[] = []
): ReadinessSummary {
	// A released number keeps its card for a while but no longer counts as one of the business's numbers.
	const kept = allCards
		.map((card, index) => ({ card, number: allNumbers[index] }))
		.filter(({ card }) => !card.released);
	const numbers = kept.map(({ number }) => number);
	const cards = kept.map(({ card }) => card);
	const counts: Partial<Record<ReadinessStatus, number>> = {};
	for (const card of cards) {
		if (card.status) counts[card.status] = (counts[card.status] ?? 0) + 1;
	}
	const reach = new Map<string, boolean>();
	numbers.forEach((number, index) => {
		for (const code of numberCountries(number)) {
			reach.set(code, (reach.get(code) ?? false) || cards[index].can_text);
		}
	});
	for (const destination of destinations) {
		if (destination.status === 'off') continue;
		const texts = numbers.some(
			(number, index) => cards[index].can_text && reachOf(number).includes(destination.country)
		);
		reach.set(destination.country, destination.status === 'ready' && texts);
	}
	const countries = [...reach.entries()]
		.map(([code, ready]) => ({ code, name: countryDisplayName(code), ready }))
		.sort((a, b) => a.name.localeCompare(b.name));
	const waiting = cards.filter((card) => !card.can_text);
	return {
		total: cards.length,
		can_text: cards.filter((card) => card.can_text).length,
		needs_you: cards
			.filter((card) => card.status && NEEDS_YOU.includes(card.status))
			.map((card) => card.name),
		only_waiting_line: waiting.length === 1 && waiting[0].line ? waiting[0].line : null,
		counts,
		countries
	};
}

const WORDS = ['No', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine'];
function spelled(count: number) {
	return WORDS[count] ?? String(count);
}

function joinNames(names: string[]) {
	if (names.length <= 1) return names.join('');
	return `${names.slice(0, -1).join(', ')} and ${names[names.length - 1]}`;
}

/** The big count: "2 of 4", or "All 3" when every number of several can text. */
export function summaryCount(summary: ReadinessSummary) {
	return summary.total > 1 && summary.can_text === summary.total
		? `All ${summary.total}`
		: `${summary.can_text} of ${summary.total}`;
}

/** The one line under the count, naming what needs the business, or saying nothing does. */
export function summaryLine(summary: ReadinessSummary) {
	const waiting = summary.total - summary.can_text;
	const parts: string[] = [];
	if (waiting > 0) {
		parts.push(
			summary.can_text === 0 && waiting === 1
				? 'Your first number is on its way.'
				: `${spelled(waiting)} more ${waiting === 1 ? 'is on its' : 'are on their'} way.`
		);
	}
	if (summary.needs_you.length === 1)
		parts.push(`${summary.needs_you[0]} needs one thing from you.`);
	else if (summary.needs_you.length > 1)
		parts.push(`${joinNames(summary.needs_you)} each need one thing from you.`);
	else if (waiting === 0) {
		const ready = summary.countries.filter((country) => country.ready);
		parts.push(
			ready.length === 1
				? `Nothing needs you. Customers in ${ready[0].name} get your texts.`
				: `Nothing needs you. Customers in all ${spelled(ready.length).toLowerCase()} countries get your texts.`
		);
	} else parts.push(summary.only_waiting_line ?? 'Nothing needs you right now.');
	return parts.join(' ');
}

export const numberReadinessKey = ['settings', 'communications', 'sms', 'readiness'] as const;

export async function fetchNumberReadiness(): Promise<ReadinessHome> {
	const response = await fetch('/api/settings/communications/sms/readiness');
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw httpError(response, result.error ?? 'Your numbers could not be loaded.');
	return result as ReadinessHome;
}
