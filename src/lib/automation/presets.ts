// Contractor Settings Part 6C: the code-owned platform preset library.
//
// A preset is one versioned, platform-authored starting point (docs/automation-behavior-contract.md
// § Recipe definition and lifecycle: "Preset selection copies the current platform preset into a new
// organization draft and records lineage for explanation only. The organization copy is independent."). It
// lives in code — there is no owner preset editor in 6C — so choosing one creates no server record; the
// builder loads its blueprint as a local draft and the first Save draft is the first write.
//
// Blueprints ship each send-email step with friendly starter copy (subject + body) that uses only the
// allow-listed variables (email-variables.ts). The organization edits it in the builder before activating;
// nothing here references another tenant's data.

import type { AuthoredDefinition } from '$lib/automation/authoring';
import { AUTOMATION_SCHEMA_VERSION } from '$lib/automation/catalog';

export type AutomationPreset = {
	key: string;
	version: number;
	name: string;
	// Plain-English purpose shown on the preset card and as builder context.
	summary: string;
	triggerKey: string;
	channels: Array<'email' | 'sms'>;
	// The starting definition the builder loads locally. Independent of this platform preset once copied.
	blueprint: AuthoredDefinition;
};

// The recommended Quote follow-up: two editable email reminders at day 3 and day 7 after a delivered quote,
// which stop the moment the quote stops awaiting a response. Delays and the status condition are editable in
// the builder within effective platform limits.
const quoteFollowUp: AutomationPreset = {
	key: 'quote_follow_up',
	version: 1,
	name: 'Quote follow-up',
	summary:
		'After a quote is delivered, send two friendly reminders — at day 3 and day 7 — and stop as soon as the customer responds.',
	triggerKey: 'quote.delivery_succeeded',
	channels: ['email'],
	blueprint: {
		schema_version: AUTOMATION_SCHEMA_VERSION,
		trigger: { key: 'quote.delivery_succeeded', config: {} },
		conditions: [{ key: 'quote.current_status', config: { statuses: ['awaiting_response'] } }],
		steps: [
			{ type: 'wait', key: 'wait.relative_delay', config: { unit: 'days', amount: 3 } },
			{
				type: 'action',
				key: 'action.send_email',
				config: {
					subject: 'Quick follow-up on your quote {{quote_number}}',
					body:
						'Hi {{customer_name}},\n\n' +
						'Just checking in on the quote we sent over ({{quote_number}}). ' +
						'You can review it anytime here: {{quote_link}}\n\n' +
						'Happy to answer any questions.\n\n' +
						'Thanks,\n{{business_name}}'
				}
			},
			{ type: 'wait', key: 'wait.relative_delay', config: { unit: 'days', amount: 4 } },
			{
				type: 'action',
				key: 'action.send_email',
				config: {
					subject: 'Still interested in quote {{quote_number}}?',
					body:
						'Hi {{customer_name}},\n\n' +
						'We wanted to follow up one more time on your quote {{quote_number}}. ' +
						"Here's the link if you'd like to take another look: {{quote_link}}\n\n" +
						"If now isn't the right time, just let us know.\n\n" +
						'Thanks,\n{{business_name}}'
				}
			}
		],
		stops: [
			{ key: 'stop.quote_approved' },
			{ key: 'stop.quote_declined' },
			{ key: 'stop.changes_requested' },
			{ key: 'stop.recipient_invalid' },
			{ key: 'stop.preferences_invalid' },
			{ key: 'stop.customer_reply' }
		]
	}
};

// CRM launch readiness Part 4: the website speed-to-lead starter (HighLevel's editable workflow model). The visitor
// already sees an on-screen receipt and the team is alerted by the Inquiry alerts setting, so the recipe itself
// is one delayed reply: if nobody on the team has replied within five minutes, text the customer when they agreed
// to texts, else email them. Jafar chose one message over an instant receipt plus a follow-up (2026-09-17). A
// delivered staff reply stops it; a customer reply pauses it. The wait and the copy are starting values only.
const websiteSpeedToLead: AutomationPreset = {
	key: 'website_speed_to_lead',
	version: 1,
	name: 'Website inquiry quick reply',
	summary:
		'When someone sends your website form or chat and nobody on your team has replied within 5 minutes, text them (or email them if texting is not possible).',
	triggerKey: 'website_inquiry.received',
	channels: ['sms', 'email'],
	blueprint: {
		schema_version: AUTOMATION_SCHEMA_VERSION,
		trigger: { key: 'website_inquiry.received', config: {} },
		conditions: [],
		steps: [
			{ type: 'wait', key: 'wait.relative_delay', config: { unit: 'minutes', amount: 5 } },
			{
				type: 'action',
				key: 'action.send_customer_message',
				config: {
					sms_body:
						'Hi {{customer_name}}, thanks for contacting {{business_name}}! ' +
						"We got your message and we'll be in touch shortly. " +
						'What is the best time to reach you?',
					email_subject: 'Thanks for contacting {{business_name}}',
					email_body:
						'Hi {{customer_name}},\n\n' +
						"Thanks for reaching out. We got your message and we'll be in touch shortly.\n\n" +
						'If there is a best time to reach you, just reply to this email.\n\n' +
						'Thanks,\n{{business_name}}'
				}
			}
		],
		stops: [{ key: 'stop.inquiry_staff_reply' }, { key: 'stop.inquiry_customer_reply' }]
	}
};

export const AUTOMATION_PRESETS: readonly AutomationPreset[] = [quoteFollowUp, websiteSpeedToLead];

const PRESETS_BY_KEY = new Map(AUTOMATION_PRESETS.map((preset) => [preset.key, preset]));

export function getAutomationPreset(key: string): AutomationPreset | undefined {
	return PRESETS_BY_KEY.get(key);
}
