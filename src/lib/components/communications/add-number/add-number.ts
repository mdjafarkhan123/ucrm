import type { NumberKind, NumberType } from '$lib/communications/sms-number-shop';
import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
import worldIcon from '@tabler/icons/outline/world.svg?raw';
import deviceMobileIcon from '@tabler/icons/outline/device-mobile.svg?raw';
import flagIcon from '@tabler/icons/outline/flag.svg?raw';
import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
import fileCheckIcon from '@tabler/icons/outline/file-check.svg?raw';
import hourglassIcon from '@tabler/icons/outline/hourglass.svg?raw';
import shoppingCartIcon from '@tabler/icons/outline/shopping-cart.svg?raw';
import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
import messageIcon from '@tabler/icons/outline/message.svg?raw';

// What the Add number tiles show for each kind of number in a country. Local, toll-free and mobile always show (as
// GoHighLevel's search does), greyed with the reason when the country can't text from them; a national kind shows
// only where Twilio sells one.

export type NextStep = { icon: string; tone: string; title: string; hint: string };

export type KindBand = { tone: 'informative' | 'warning' | 'inactive'; text: string };

export type KindChoice = {
	numberType: NumberType;
	kind: NumberKind | undefined;
	available: boolean;
	icon: string;
	description: string;
	band: KindBand | null;
};

// Country names that read with "the" in a sentence ("Not sold in the United States").
const NAMES_WITH_THE = new Set(['US', 'GB', 'NL', 'PH', 'AE', 'DO', 'BS', 'CZ', 'CF', 'KY', 'GM', 'MV']);

/** A country's name as it reads mid-sentence. */
export function countryInSentence(code: string, name: string): string {
	return NAMES_WITH_THE.has(code) ? `the ${name}` : name;
}

const ALWAYS_SHOWN: NumberType[] = ['local', 'toll_free', 'mobile'];

const ICONS: Record<NumberType, string> = {
	local: mapPinIcon,
	toll_free: worldIcon,
	mobile: deviceMobileIcon,
	national: flagIcon
};

const DESCRIPTIONS: Record<NumberType, string> = {
	local: 'A number with a local area code. Customers know it’s nearby.',
	toll_free: 'An 800-style number that works across the whole country.',
	mobile: 'A mobile number. In some countries only these can text.',
	national: 'A number for the whole country, without a local area code.'
};

function bandFor(kind: NumberKind | undefined, countryName: string): KindBand | null {
	if (!kind) return { tone: 'inactive', text: `Not sold in ${countryName}` };
	if (!kind.can_text) {
		return kind.can_call
			? { tone: 'inactive', text: `Calls only in ${countryName}` }
			: { tone: 'inactive', text: `Not sold for texting in ${countryName}` };
	}
	if (kind.monthly_minor === null) return { tone: 'inactive', text: 'Uplift is setting its price' };
	if (kind.needs === 'paperwork_first') return { tone: 'warning', text: 'Paperwork needed first' };
	if (kind.needs === 'register_after') {
		return kind.number_type === 'toll_free'
			? { tone: 'informative', text: 'Needs a toll-free check to text' }
			: { tone: 'informative', text: 'Needs your business registered to text' };
	}
	return null;
}

export function kindChoices(kinds: NumberKind[], countryName: string): KindChoice[] {
	const shown = [
		...ALWAYS_SHOWN,
		...kinds.map((kind) => kind.number_type).filter((type) => !ALWAYS_SHOWN.includes(type))
	];
	return shown.map((numberType) => {
		const kind = kinds.find((candidate) => candidate.number_type === numberType);
		return {
			numberType,
			kind,
			available: Boolean(kind?.can_text && kind.monthly_minor !== null),
			icon: ICONS[numberType],
			description: DESCRIPTIONS[numberType],
			band: bandFor(kind, countryName)
		};
	});
}

export function kindIcon(numberType: NumberType): string {
	return ICONS[numberType];
}

/** "Austin, TX · Local" */
export function placeLine(
	locality: string | null,
	region: string | null,
	typeLabel: string
): string {
	const place = [locality, region].filter(Boolean).join(', ');
	return place ? `${place} · ${typeLabel}` : typeLabel;
}

/** Whether a country's numbers register for texting after buying (US and Canada, 10DLC or toll-free check). */
export function registersAfter(countryCode: string): boolean {
	return countryCode === 'US' || countryCode === 'CA';
}

/** The three "What happens next" boxes, before buying (`bought` false) or after. */
export function nextSteps(input: {
	countryCode: string;
	numberType: NumberType;
	paperworkFirst: boolean;
	bought: boolean;
}): NextStep[] {
	if (input.paperworkFirst) {
		return [
			{
				icon: fileTextIcon,
				tone: 'warning',
				title: 'Send your paperwork',
				hint: 'Business details and documents · about 10 minutes'
			},
			{
				icon: hourglassIcon,
				tone: 'informative',
				title: 'Phone company checks it',
				hint: 'Usually 1–3 business days'
			},
			{
				icon: shoppingCartIcon,
				tone: 'inactive',
				title: 'Buy and start texting',
				hint: 'Pick a number once approved'
			}
		];
	}
	const yours: NextStep = {
		icon: circleCheckIcon,
		tone: 'success',
		title: 'The number is yours',
		hint: input.bought ? 'Done' : 'Right after you buy'
	};
	const ready: NextStep = {
		icon: messageIcon,
		tone: 'inactive',
		title: 'Ready to text',
		hint: registersAfter(input.countryCode)
			? 'Once the registration is approved'
			: 'Once Uplift confirms it can text'
	};
	if (!registersAfter(input.countryCode)) {
		return [
			yours,
			{
				icon: hourglassIcon,
				tone: 'informative',
				title: 'Uplift checks the rules',
				hint: 'What texting from this country needs'
			},
			ready
		];
	}
	const tollFree = input.numberType === 'toll_free';
	return [
		yours,
		{
			icon: fileCheckIcon,
			tone: 'warning',
			title: tollFree ? 'Toll-free check' : 'Register your business',
			hint: input.bought
				? 'Business details needed'
				: 'Business details needed · approval takes a few days'
		},
		ready
	];
}
