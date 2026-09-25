// Google review campaign Part 2: what the customer's feedback page draws. The public page builds it from the
// review request link; the review settings preview builds it from the settings being edited.

import type { ReviewFeedbackForm } from './settings';

export type ReviewFeedbackPageModel = {
	business: { name: string; logo_url: string | null };
	customer_first_name: string | null;
	google_review_url: string | null;
	routing_enabled: boolean;
	routing_google_min_rating: number;
	feedback_form: ReviewFeedbackForm;
	feedback_submitted: boolean;
};

export const REVIEW_STAR_LABELS = ['Terrible', 'Poor', 'Okay', 'Good', 'Excellent'] as const;
