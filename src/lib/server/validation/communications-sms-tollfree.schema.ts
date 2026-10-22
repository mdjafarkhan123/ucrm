import { z } from 'zod';
import { smsRegistrationAnswersSchema } from './communications-sms-registration.schema';

// The toll-free check's answers (Stage 10 Part 4b). The business answers are the US registration's own, so a
// business that registered already sees them filled in; the toll-free check adds pictures of how customers agree
// to texts, which Twilio requires as public links (OptInImageUrls).

const publicImageUrl = z
	.string()
	.trim()
	.url('Enter a complete web address, including https://.')
	.max(2048)
	.refine((value) => value.startsWith('https://'), {
		message: 'The picture must be at a web address beginning with https://.'
	});

export const smsTollfreeAnswersSchema = z
	.object({
		business: smsRegistrationAnswersSchema,
		opt_in_image_urls: z
			.array(publicImageUrl)
			.min(1, 'Add a picture of how customers agree to your texts.')
			.max(5, 'Add no more than five pictures.')
	})
	.superRefine((data, ctx) => {
		// Twilio's toll-free check names one of its own ways customers agree; "another method" has no match there.
		if (data.business.messaging.consent_method === 'other') {
			ctx.addIssue({
				code: 'custom',
				path: ['business', 'messaging', 'consent_method'],
				message: 'Choose how customers agree to your texts.'
			});
		}
	});

export type SmsTollfreeAnswers = z.infer<typeof smsTollfreeAnswersSchema>;
