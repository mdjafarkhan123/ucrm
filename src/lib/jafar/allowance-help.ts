// Package builder: what each allowance means, in everyday words, for Jafar while he builds a package.
// Written from the behavior contract (docs/package-builder-behavior-contract.md and
// docs/contractor-email-contract.md); change them together.

export type AllowanceHelp = {
	/** One sentence: what this limit controls. */
	what: string;
	/** What is counted, and when the count goes up or down. */
	counts: string;
	/** What the business sees on reaching the limit. */
	atLimit: string;
	/** A worked example. */
	example: string;
};

export const ALLOWANCE_HELP: Record<string, AllowanceHelp> = {
	employee_seats: {
		what: 'How many people can have a login for the business.',
		counts:
			'The owner, every active staff member, and every invitation still waiting to be accepted. A seat is freed when someone leaves or an invitation expires.',
		atLimit:
			'The business cannot add or invite anyone else until a seat frees up. Everyone already on the team keeps working.',
		example:
			'A limit of 5 means the owner and 4 more people, counting invitations not yet accepted.'
	},
	operational_email_recipients: {
		what: 'The everyday emails the app sends for the business to its customers.',
		counts:
			'Confirmations, quotes and follow-ups, visit updates, invoices and reminders, receipts, review requests, and staff replies. Each person an email goes to counts once. It starts again every month, also on yearly packages.',
		atLimit:
			'Emails that matter most (quotes and invoices a customer asked for, receipts, security notices, direct replies) never stop. Optional emails past the allowance are paid from the business’s prepaid Communication Balance, and wait if the balance is too low.',
		example:
			'A limit of 1,000 a month covers about 1,000 emails to customers before optional ones start using their balance.'
	},
	essential_email_recipients: {
		what: 'A safety cushion for the emails a business can never go without.',
		counts:
			'Quotes and invoices customers asked for, receipts, security notices and direct replies. It is always 10% of the everyday email allowance, so you do not set it here.',
		atLimit:
			'These emails keep sending. When the cushion is used up, the business and you are warned, and nothing is blocked.',
		example: 'With 1,000 everyday emails, the cushion is 100 more essential ones.'
	},
	website_chat_widgets: {
		what: 'How many chat buttons the business can put on its websites.',
		counts:
			'Each chat widget that exists at one time. Deleting a widget frees the space immediately.',
		atLimit:
			'The business cannot create another widget. Widgets already on their websites keep working.',
		example: 'A limit of 2 suits a business with a main site and one landing page.'
	},
	website_chat_accepted_conversations: {
		what: 'How many new website chats the business can take each month.',
		counts:
			'A chat is counted when its first message is accepted, not when a visitor only opens the widget. It starts again every month, also on yearly packages.',
		atLimit:
			'New chats are paused with a clear message to the business. Chats already started can carry on to the end.',
		example: 'A limit of 100 means 100 new people can start a chat in a month.'
	},
	marketing_email_recipients: {
		what: 'How many marketing emails the business can send to customers each month.',
		counts:
			'Promotions, offers and campaigns, with each person it is sent to counting once. It starts again every month, also on yearly packages.',
		atLimit:
			'Marketing sends stop with a clear message. Everyday and essential emails are not affected.',
		example: 'A limit of 2,000 allows one campaign to 2,000 customers, or four to 500.'
	},
	automation_active_recipes: {
		what: 'How many automations can be switched on at the same time.',
		counts:
			'Each automation that is currently on. Paused or switched-off ones do not count. Resuming a paused automation counts again.',
		atLimit:
			'The business cannot switch on another one until it turns something off. Their saved automations are never deleted.',
		example: 'A limit of 5 means five follow-up automations running together.'
	}
};
