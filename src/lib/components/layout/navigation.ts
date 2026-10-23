import dashboardIcon from '@tabler/icons/outline/layout-dashboard.svg?raw';
import usersIcon from '@tabler/icons/outline/users.svg?raw';
import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';
import fileInvoiceIcon from '@tabler/icons/outline/file-invoice.svg?raw';
import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
import toolsIcon from '@tabler/icons/outline/tools.svg?raw';
import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
import clockIcon from '@tabler/icons/outline/clock-hour-4.svg?raw';
import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
import messagesIcon from '@tabler/icons/outline/messages.svg?raw';
import messageTextIcon from '@tabler/icons/outline/message-2.svg?raw';
import hammerIcon from '@tabler/icons/outline/hammer.svg?raw';
import packageIcon from '@tabler/icons/outline/package.svg?raw';
import buildingIcon from '@tabler/icons/outline/building.svg?raw';
import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
import shieldCheckIcon from '@tabler/icons/outline/shield-check.svg?raw';
import settingsIcon from '@tabler/icons/outline/settings.svg?raw';
import mailIcon from '@tabler/icons/outline/mail.svg?raw';
import routeIcon from '@tabler/icons/outline/route.svg?raw';
import starIcon from '@tabler/icons/outline/star.svg?raw';
import speakerphoneIcon from '@tabler/icons/outline/speakerphone.svg?raw';
import trendingUpIcon from '@tabler/icons/outline/trending-up.svg?raw';
import usersGroupIcon from '@tabler/icons/outline/users-group.svg?raw';
import chartBarIcon from '@tabler/icons/outline/chart-bar.svg?raw';
import filesIcon from '@tabler/icons/outline/files.svg?raw';
import rocketIcon from '@tabler/icons/outline/rocket.svg?raw';
import listCheckIcon from '@tabler/icons/outline/list-check.svg?raw';
import targetIcon from '@tabler/icons/outline/target.svg?raw';
import homeIcon from '@tabler/icons/outline/home.svg?raw';
import clipboardListIcon from '@tabler/icons/outline/clipboard-list.svg?raw';
import layoutKanbanIcon from '@tabler/icons/outline/layout-kanban.svg?raw';
import folderOpenIcon from '@tabler/icons/outline/folder-open.svg?raw';

/** The colour family an icon takes from what it opens: a record, a part of the app, or your business. */
export type NavTone =
	| 'inactive'
	| 'time'
	| 'conversation'
	| 'client'
	| 'request'
	| 'growth'
	| 'job'
	| 'quote'
	| 'invoice'
	| 'review';

/** `count` is a number waiting for attention, such as unread support conversations. Zero shows nothing. */
export type NavItem = {
	label: string;
	href: string;
	icon: string;
	/** Colours the icon; without it the icon stays the neutral icon colour. */
	tone?: NavTone;
	unavailable?: boolean;
	count?: number;
	/** Other pages that belong to this item, so it stays highlighted while one of them is open. */
	matches?: string[];
};
/** `pinned` groups sit at the bottom of the sidebar, behind a divider — Settings lives there. */
export type NavGroup = { label?: string; items: NavItem[]; pinned?: boolean };

export const iconMap: Record<string, string> = {
	dashboard: dashboardIcon,
	users: usersIcon,
	inbox: inboxIcon,
	fileInvoice: fileInvoiceIcon,
	fileText: fileTextIcon,
	tools: toolsIcon,
	calendar: calendarIcon,
	clock: clockIcon,
	receipt: receiptIcon,
	messages: messagesIcon,
	messageText: messageTextIcon,
	hammer: hammerIcon,
	package: packageIcon,
	building: buildingIcon,
	alertTriangle: alertTriangleIcon,
	shieldCheck: shieldCheckIcon,
	settings: settingsIcon,
	mail: mailIcon,
	route: routeIcon,
	star: starIcon,
	speakerphone: speakerphoneIcon,
	trendingUp: trendingUpIcon,
	usersGroup: usersGroupIcon,
	chartBar: chartBarIcon,
	files: filesIcon,
	rocket: rocketIcon,
	listCheck: listCheckIcon,
	target: targetIcon,
	home: homeIcon,
	clipboardList: clipboardListIcon,
	layoutKanban: layoutKanbanIcon,
	folderOpen: folderOpenIcon
};

export function activeNavigationHref(groups: NavGroup[], pathname: string) {
	return groups
		.flatMap((group) => group.items)
		.filter(
			(item) =>
				!item.unavailable &&
				[item.href, ...(item.matches ?? [])].some(
					(href) => pathname === href || (href !== '/' && pathname.startsWith(`${href}/`))
				)
		)
		.sort((left, right) => right.href.length - left.href.length)[0]?.href;
}
