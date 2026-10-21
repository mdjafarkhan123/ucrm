import {
	MARKETING_SERVICE_SUMMARY_MAX_ITEMS,
	type MarketingBlockType
} from '$lib/marketing/campaign-content';
import photoIcon from '@tabler/icons/outline/photo.svg?raw';
import headingIcon from '@tabler/icons/outline/heading.svg?raw';
import pilcrowIcon from '@tabler/icons/outline/pilcrow.svg?raw';
import clickIcon from '@tabler/icons/outline/click.svg?raw';
import separatorIcon from '@tabler/icons/outline/separator-horizontal.svg?raw';
import listCheckIcon from '@tabler/icons/outline/list-check.svg?raw';

// What each kind of email block looks like in the New campaign Email step (design skill `layout.md` → New
// campaign · Email step): its icon, and the quiet line the Add a block menu shows under its name. The block
// rows and that menu both read this, so a block looks the same wherever it appears.
export const BLOCK_TYPE_ICONS: Record<MarketingBlockType, string> = {
	image: photoIcon,
	heading: headingIcon,
	text: pilcrowIcon,
	button: clickIcon,
	divider: separatorIcon,
	service_summary: listCheckIcon
};

export const BLOCK_TYPE_HINTS: Record<MarketingBlockType, string> = {
	image: 'A photo, with a link if you like',
	heading: 'A big line of text',
	text: 'A paragraph',
	button: 'A link customers tap',
	divider: 'A line between parts',
	service_summary: `Up to ${MARKETING_SERVICE_SUMMARY_MAX_ITEMS} services from your price list`
};
