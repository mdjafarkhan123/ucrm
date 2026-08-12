import { z } from 'zod';

export const ownerSettingsSchema = z.object({
	privacy_policy_url: z.string().trim().url('Enter a valid privacy-policy URL.').max(500),
	privacy_policy_version: z.string().trim().min(1, 'Enter a privacy-policy version.').max(40),
	payment_instructions: z
		.string()
		.trim()
		.min(1, 'Enter the payment instructions shown to prospects.')
		.max(5000),
	sender_display_name: z.string().trim().min(1, 'Enter a sender display name.').max(200),
	reply_to_address: z
		.string()
		.trim()
		.toLowerCase()
		.email('Enter a valid reply-to email address.')
		.max(254),
	alert_recipient_emails: z
		.array(z.string().trim().toLowerCase().email('Enter a valid email address.').max(254))
		.min(1, 'At least one alert recipient is required.')
		.max(10, 'No more than 10 alert recipients.')
});
