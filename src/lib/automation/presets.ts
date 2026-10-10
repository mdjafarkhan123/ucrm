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
import {
	APPOINTMENT_REMINDER_DEFAULT,
	AUTOMATION_SCHEMA_VERSION,
	INVOICE_REMINDER_DEFAULT
} from '$lib/automation/catalog';

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

// Google review campaign Part 4B: the ready-made automatic ask (HighLevel's Workflow "Review Request" action;
// brief § How the automation is set up). One step: the message, style, first-send delay and reminders all come
// from Review settings, so there is no copy here. SMS by default; recurring jobs stay off until the contractor
// picks "after every N completed visits". It cannot be activated without a saved Google review link.
const googleReviewRequest: AutomationPreset = {
	key: 'google_review_request',
	version: 1,
	name: 'Ask for a Google review',
	summary:
		"When a job's work is completed, ask the customer for a Google review with the message and reminders from your Review settings.",
	triggerKey: 'job.work_completed',
	channels: ['sms'],
	blueprint: {
		schema_version: AUTOMATION_SCHEMA_VERSION,
		trigger: { key: 'job.work_completed', config: {} },
		conditions: [],
		steps: [{ type: 'action', key: 'action.send_review_request', config: { channel: 'sms' } }],
		stops: [{ key: 'stop.job_reopened' }, { key: 'stop.client_review_opt_out' }]
	}
};

// Client reminders Part 3: one reminder before each visit or assessment, 1 day before at the visit's own time of
// day, as Jobber does. Like every customer message it is off until the owner turns it on; the timing and copy are
// starting values the owner can change.
const visitReminder: AutomationPreset = {
	key: 'visit_reminder',
	version: 1,
	name: 'Visit reminder',
	summary:
		'Email each customer a reminder 1 day before their visit or assessment. If the visit moves, the reminder moves with it.',
	triggerKey: 'appointment.reminder_due',
	channels: ['email'],
	blueprint: {
		schema_version: AUTOMATION_SCHEMA_VERSION,
		trigger: { key: 'appointment.reminder_due', config: { ...APPOINTMENT_REMINDER_DEFAULT } },
		conditions: [],
		steps: [
			{
				type: 'action',
				key: 'action.send_appointment_email',
				config: {
					subject: 'Reminder: {{business_name}} is visiting {{appointment_when}}',
					body:
						'Hi {{customer_name}},\n\n' +
						'This is a friendly reminder that {{business_name}} is scheduled to visit ' +
						'{{appointment_when}}.\n\n' +
						'Address: {{appointment_address}}\n\n' +
						'If you need to change the time, just reply to this email.\n\n' +
						'Thanks,\n{{business_name}}'
				}
			}
		],
		stops: [{ key: 'stop.appointment_not_ahead' }, { key: 'stop.client_reminder_opt_out' }]
	}
};

// Client reminders Part 4: a one-time "You're booked" email per job or assessment (Jobber's booking confirmation;
// Housecall Pro's send-on-schedule with a "Notify customer" box), and an update when the visit moves. Both are off
// until the owner turns them on.
const bookingConfirmation: AutomationPreset = {
	key: 'booking_confirmation',
	version: 1,
	name: 'Booking confirmation',
	summary:
		'Email the customer once when their job or assessment is booked. A recurring job gets one confirmation, not one per visit.',
	triggerKey: 'appointment.booked',
	channels: ['email'],
	blueprint: {
		schema_version: AUTOMATION_SCHEMA_VERSION,
		trigger: { key: 'appointment.booked', config: {} },
		conditions: [],
		steps: [
			{
				type: 'action',
				key: 'action.send_appointment_email',
				config: {
					subject: "You're booked with {{business_name}}",
					body:
						'Hi {{customer_name}},\n\n' +
						"You're booked! {{business_name}} will see you {{appointment_when}}.\n\n" +
						'Address: {{appointment_address}}\n\n' +
						'If you need to change the time, just reply to this email.\n\n' +
						'Thanks,\n{{business_name}}'
				}
			}
		],
		stops: [{ key: 'stop.appointment_not_ahead' }, { key: 'stop.client_reminder_opt_out' }]
	}
};

const visitMoved: AutomationPreset = {
	key: 'visit_moved',
	version: 1,
	name: 'Visit moved',
	summary: 'Email the customer the new date and time when a booked visit or assessment is moved.',
	triggerKey: 'appointment.rescheduled',
	channels: ['email'],
	blueprint: {
		schema_version: AUTOMATION_SCHEMA_VERSION,
		trigger: { key: 'appointment.rescheduled', config: {} },
		conditions: [],
		steps: [
			{
				type: 'action',
				key: 'action.send_appointment_email',
				config: {
					subject: 'Your visit with {{business_name}} has moved',
					body:
						'Hi {{customer_name}},\n\n' +
						'Your visit with {{business_name}} has moved to {{appointment_when}}.\n\n' +
						'Address: {{appointment_address}}\n\n' +
						"If the new time doesn't work for you, just reply to this email.\n\n" +
						'Thanks,\n{{business_name}}'
				}
			}
		],
		stops: [{ key: 'stop.appointment_not_ahead' }, { key: 'stop.client_reminder_opt_out' }]
	}
};

// Client reminders Part 5: two reminders for an unpaid invoice, 1 day and 7 days after its due date — the first two
// after-due steps in Jobber's payment-reminder advice. Each carries the balance and a link to pay.
const overdueInvoiceReminders: AutomationPreset = {
	key: 'overdue_invoice_reminders',
	version: 1,
	name: 'Overdue invoice reminders',
	summary:
		'Email the customer when an invoice is 1 day overdue, and again at 7 days, with a link to pay. Paying the invoice stops the reminders.',
	triggerKey: 'invoice.past_due',
	channels: ['email'],
	blueprint: {
		schema_version: AUTOMATION_SCHEMA_VERSION,
		trigger: { key: 'invoice.past_due', config: { ...INVOICE_REMINDER_DEFAULT } },
		conditions: [],
		steps: [
			{
				type: 'action',
				key: 'action.send_invoice_email',
				config: {
					subject: 'Invoice {{invoice_number}} from {{business_name}} is past due',
					body:
						'Hi {{customer_name}},\n\n' +
						'This is a friendly reminder that invoice {{invoice_number}} was due on {{invoice_due_date}}. ' +
						'The amount still owed is {{invoice_balance}}.\n\n' +
						'You can view and pay it here: {{invoice_link}}\n\n' +
						'If you have already paid, thank you, and please ignore this email.\n\n' +
						'Thanks,\n{{business_name}}'
				}
			},
			{ type: 'wait', key: 'wait.relative_delay', config: { unit: 'days', amount: 6 } },
			{
				type: 'action',
				key: 'action.send_invoice_email',
				config: {
					subject: 'Second reminder: invoice {{invoice_number}} is past due',
					body:
						'Hi {{customer_name}},\n\n' +
						'Invoice {{invoice_number}} from {{business_name}} is now a week past its due date of ' +
						'{{invoice_due_date}}. The amount still owed is {{invoice_balance}}.\n\n' +
						'You can view and pay it here: {{invoice_link}}\n\n' +
						'If something is holding up payment, just reply to this email.\n\n' +
						'Thanks,\n{{business_name}}'
				}
			}
		],
		stops: [{ key: 'stop.invoice_settled' }, { key: 'stop.client_invoice_reminder_opt_out' }]
	}
};

// Client reminders Part 6: a thank-you when a job's work is completed, as Jobber's Job Follow-ups. It goes out
// during business hours; the owner can add a wait before it. Off until the owner turns it on.
const jobFollowUp: AutomationPreset = {
	key: 'job_follow_up',
	version: 1,
	name: 'Job follow-up',
	summary:
		"Email the customer a thank-you when a job's work is completed, during your business hours. Each job gets one.",
	triggerKey: 'job.work_completed',
	channels: ['email'],
	blueprint: {
		schema_version: AUTOMATION_SCHEMA_VERSION,
		trigger: { key: 'job.work_completed', config: {} },
		conditions: [],
		steps: [
			{
				type: 'action',
				key: 'action.send_job_email',
				config: {
					subject: 'Thank you from {{business_name}}',
					body:
						'Hi {{customer_name}},\n\n' +
						'Thank you for choosing {{business_name}}. We have finished {{job_title}} and hope ' +
						'everything is just how you wanted it.\n\n' +
						'If anything needs another look, or you have a question, just reply to this email.\n\n' +
						'Thanks again,\n{{business_name}}'
				}
			}
		],
		stops: [{ key: 'stop.job_reopened' }, { key: 'stop.client_review_opt_out' }]
	}
};

export const AUTOMATION_PRESETS: readonly AutomationPreset[] = [
	quoteFollowUp,
	websiteSpeedToLead,
	googleReviewRequest,
	visitReminder,
	bookingConfirmation,
	visitMoved,
	overdueInvoiceReminders,
	jobFollowUp
];

const PRESETS_BY_KEY = new Map(AUTOMATION_PRESETS.map((preset) => [preset.key, preset]));

export function getAutomationPreset(key: string): AutomationPreset | undefined {
	return PRESETS_BY_KEY.get(key);
}
