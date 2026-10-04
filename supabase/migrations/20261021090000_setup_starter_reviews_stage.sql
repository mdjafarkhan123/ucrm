-- Client onboarding B10: the approved starter content's stage 10, "Review requests"
-- (docs/client-onboarding-setup-content-blueprint.md), loaded into the setup draft for Jafar to review and
-- publish. Nothing a client sees changes until he publishes it. The stage is new, so no answer is affected, and
-- it is shown only to a client whose package includes Review requests.
--
-- Every customer is asked the same way and always sees both choices on the review page — leave a Google review
-- or tell the business privately (plan §3.7; docs/google-review-campaign-owner-brief.md "Review routing").
-- Nothing here asks the client which customers to leave out or offers a reward, so the setup cannot turn into
-- review gating or a paid review.
--
-- The answers match what the CRM's Review settings can already do (src/lib/reviews/settings.ts), so Uplift
-- copies them across: email or text, the three message styles, and the ready-made two reminders 3 and 5 days
-- after the first message. Texting is offered only when the package includes Calls and texting.
--
-- Facts given in earlier stages are confirmed, not typed again: the business name and the times automatic texts
-- may go out; a client not asked one of those is asked it here instead. The Google link is asked afresh: the
-- Google stage asks for it only on some answers, so it cannot be shown back for confirmation. The review
-- page shows the logo from Brand, photos and proof — or just the name until there is one — so the logo is not
-- asked again.

select private.setup_load_starter_stage(
	'reviews',
	'Review requests',
	'How Uplift asks your customers for an honest Google review after a job — politely, and never more than needed.',
	'reviews',
	$items$[
		{"type": "heading", "label": "Where reviews go",
			"hint": "Every customer gets the same message and sees two choices: leave a Google review, or tell you privately. Nobody is kept away from Google."},
		{"type": "question", "fact_key": "reviews.google_link", "kind": "url", "required": true, "can_defer": true,
			"label": "Which Google profile should reviews go to?",
			"hint": "Find your business on Google Maps, tap Share, and copy the link. If Uplift is setting up or managing your Google profile, choose “I need Uplift’s help” and Uplift adds it."},
		{"type": "question", "fact_key": "reviews.display_name", "kind": "reuse", "reuse_from": "business.public_name",
			"required": true,
			"label": "Which business name should customers see?",
			"hint": "Shown in the message and on the review page, with the logo you shared in Brand, photos and proof."},
		{"type": "question", "fact_key": "reviews.feedback_people", "kind": "list", "max_rows": 5, "required": true,
			"label": "Who should hear about private feedback?",
			"hint": "When a customer writes to you privately, these people are told, so someone can reply quickly.",
			"list_fields": [
				{"key": "name", "label": "Name", "kind": "text", "required": true},
				{"key": "email", "label": "Email", "kind": "email", "required": true}
			]},

		{"type": "heading", "label": "When and how customers are asked",
			"hint": "Before anything goes out, Uplift shows you the exact messages, timing and who receives them. Nobody is asked automatically more than once in six months."},
		{"type": "question", "fact_key": "reviews.channel", "kind": "choice", "required": true,
			"label": "How should customers be asked?",
			"hint": "Texts start once your texting registration is approved; until then requests go by email.",
			"show_if": [{"service_key": "calls_texting"}],
			"options": [
				{"value": "sms", "label": "By text (recommended — most people read texts quickly)"},
				{"value": "email", "label": "By email"}
			]},
		{"type": "question", "fact_key": "reviews.first_send", "kind": "choice", "required": true,
			"label": "When should the first request go out?",
			"hint": "Soon after the work is done is when customers remember it best.",
			"options": [
				{"value": "job_completed", "label": "When a job’s work is finished (recommended)"},
				{"value": "visit_completed", "label": "After each finished visit"},
				{"value": "paid", "label": "When the customer has paid in full"},
				{"value": "manual", "label": "Only when I choose to send one"}
			]},
		{"type": "question", "fact_key": "reviews.reminders", "kind": "choice", "required": true,
			"label": "If a customer doesn’t respond, how many reminders should follow?",
			"hint": "Reminders stop as soon as the customer goes to Google or writes to you privately.",
			"options": [
				{"value": "two", "label": "Two — 3 and 5 days after the first message (recommended)"},
				{"value": "one", "label": "One — 3 days after the first message"},
				{"value": "none", "label": "None"}
			]},
		{"type": "question", "fact_key": "reviews.send_hours", "kind": "reuse", "reuse_from": "texting.quiet_hours",
			"required": true,
			"label": "When may review requests go out?",
			"hint": "Never at night where the customer lives, whatever is chosen here."},
		{"type": "question", "fact_key": "reviews.tone", "kind": "choice",
			"label": "How should the message sound?",
			"hint": "Optional. You see the exact words before anything goes out.",
			"options": [
				{"value": "recommended", "label": "Use Uplift’s recommended wording"},
				{"value": "friendly", "label": "Warm and friendly"},
				{"value": "professional", "label": "Polite and formal"},
				{"value": "short", "label": "Short and to the point"}
			]},
		{"type": "question", "fact_key": "reviews.tone_note", "kind": "longtext", "max_length": 500,
			"label": "Anything the message should say, or avoid?",
			"hint": "Optional. For example “sign off from Dave” or “don’t call it a survey”."},

		{"type": "heading", "label": "Past customers",
			"hint": "Customers from recent months can be asked once too, if you know them and may contact them."},
		{"type": "question", "fact_key": "reviews.past_customers", "kind": "yes_no_unsure", "required": true,
			"label": "Should past customers be asked for a review too?"},
		{"type": "question", "fact_key": "reviews.past_customer_list", "kind": "protected_file", "max_files": 5,
			"required": true, "can_defer": true,
			"label": "Upload the list of past customers to ask.",
			"hint": "A spreadsheet with each customer’s name and their phone or email. Leave it for later if they are going into your CRM with the rest of your data. Only the business owner and Uplift can open it.",
			"show_if": [{"fact_key": "reviews.past_customers", "values": ["yes"]}]},
		{"type": "question", "fact_key": "reviews.past_customers_real", "kind": "yes_no", "required": true,
			"label": "Are these all customers you have done work for, and may contact about it?",
			"hint": "Never bought or copied lists, and never people who asked you not to contact them.",
			"show_if": [{"fact_key": "reviews.past_customers", "values": ["yes"]}]},

		{"type": "heading", "label": "Honest reviews",
			"hint": "Google removes reviews — and can restrict a profile — when businesses pick who is asked or reward reviews. Consumer law in places like the UK and US can treat it as unfair, too."},
		{"type": "question", "fact_key": "reviews.same_for_everyone", "kind": "yes_no", "required": true,
			"label": "Do you agree that every customer gets the same chance to leave an honest review?",
			"hint": "Nobody is left out for being likely to give a low rating, and nobody is asked only if they seemed happy."},
		{"type": "question", "fact_key": "reviews.no_rewards", "kind": "yes_no", "required": true,
			"label": "Do you agree never to offer a reward, discount or prize for a review, or to pressure a customer?"}
	]$items$::jsonb
);
