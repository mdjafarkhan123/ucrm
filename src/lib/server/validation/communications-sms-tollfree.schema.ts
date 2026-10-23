import { z } from 'zod';
import {
	addressSchema,
	messagingSchema,
	optionalText,
	representativeSchema,
	shortText,
	smsRegistrationAnswersSchema,
	webUrl
} from './communications-sms-registration.schema';

// The toll-free check's answers (Stage 10 Part 4b/4c). The business answers start as the US registration's own,
// so a business that registered already sees them filled in. Twilio's toll-free check asks less than a 10DLC
// brand: no contact job title or position, and its registration authority falls back to OTHER, so those stay
// optional here (the form leaves them out). It adds pictures of how customers agree, sent as public links
// (OptInImageUrls), and the country the registration number belongs to.

const publicImageUrl = z
	.string()
	.trim()
	.url('Enter a complete web address, including https://.')
	.max(2048)
	.refine((value) => value.startsWith('https://'), {
		message: 'The picture must be at a web address beginning with https://.'
	});

const countryCode = z
	.string()
	.trim()
	.transform((value) => value.toUpperCase())
	.refine((value) => /^[A-Z]{2}$/.test(value), 'Choose a country.');

export const smsTollfreeBusinessSchema = z
	.object({
		legal_business_name: shortText('the legal business name', 200),
		business_type: smsRegistrationAnswersSchema.shape.business_type,
		business_registration_id_type: optionalText(40),
		business_registration_id: optionalText(100),
		/** Where the registration number was issued; the business address's country when not given. */
		business_registration_country: countryCode.optional(),
		website_url: webUrl,
		business_address: addressSchema,
		authorized_representative: representativeSchema.extend({
			business_title: optionalText(100),
			job_position: optionalText(100)
		}),
		messaging: messagingSchema
	})
	.superRefine((data, ctx) => {
		// Twilio requires a registration number from every business type except a sole proprietor; one without a
		// number must be in the US or Canada, the only places toll-free numbers are checked.
		const soleProprietor = data.business_type === 'sole_proprietorship';
		if (!soleProprietor && !data.business_registration_id) {
			ctx.addIssue({
				code: 'custom',
				path: ['business_registration_id'],
				message: 'Enter the business registration number.'
			});
		}
		if (soleProprietor && !data.business_registration_id) {
			const country = data.business_address.country_code;
			if (country !== 'US' && country !== 'CA') {
				ctx.addIssue({
					code: 'custom',
					path: ['business_address', 'country_code'],
					message: 'Without a registration number, the address must be in the US or Canada.'
				});
			}
		}
	});

export const smsTollfreeAnswersSchema = z
	.object({
		business: smsTollfreeBusinessSchema,
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

export type SmsTollfreeBusiness = z.infer<typeof smsTollfreeBusinessSchema>;
export type SmsTollfreeAnswers = z.infer<typeof smsTollfreeAnswersSchema>;
