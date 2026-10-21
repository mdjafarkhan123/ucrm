import type { MarketingGroupRuleConditionKey } from '$lib/marketing/customer-groups';
import userIcon from '@tabler/icons/outline/user.svg?raw';
import tagIcon from '@tabler/icons/outline/tag.svg?raw';
import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';
import toolIcon from '@tabler/icons/outline/tool.svg?raw';
import repeatIcon from '@tabler/icons/outline/repeat.svg?raw';
import calendarCheckIcon from '@tabler/icons/outline/calendar-check.svg?raw';
import calendarClockIcon from '@tabler/icons/outline/calendar-clock.svg?raw';
import userPlusIcon from '@tabler/icons/outline/user-plus.svg?raw';
import userXIcon from '@tabler/icons/outline/user-x.svg?raw';

// Each condition's tile is coloured by what it checks: the client, where they came from, their work,
// their schedule, or a hand-picked include / exclude. The customer group pop-up's rows and the New campaign
// Customers step's rule chips both read this, so a condition looks the same wherever it appears.
export const CONDITION_TILES: Record<MarketingGroupRuleConditionKey, { icon: string; tone: string }> =
	{
		lifecycle: { icon: userIcon, tone: 'client' },
		tags: { icon: tagIcon, tone: 'client' },
		cities: { icon: mapPinIcon, tone: 'client' },
		lead_sources: { icon: inboxIcon, tone: 'request' },
		services: { icon: toolIcon, tone: 'job' },
		work_type: { icon: repeatIcon, tone: 'job' },
		last_completed_job: { icon: calendarCheckIcon, tone: 'job' },
		upcoming_work: { icon: calendarClockIcon, tone: 'time' },
		include_client_ids: { icon: userPlusIcon, tone: 'success' },
		exclude_client_ids: { icon: userXIcon, tone: 'critical' }
	};
