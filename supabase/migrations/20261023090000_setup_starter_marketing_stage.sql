-- Client onboarding B12: the approved starter content's stage 11, "Marketing campaigns"
-- (docs/client-onboarding-setup-content-blueprint.md), loaded into the setup draft for Jafar to review and
-- publish. Nothing a client sees changes until he publishes it. The stage is new, so no answer is affected, and
-- it is shown only to a client whose package includes Marketing campaigns.
--
-- It is a brief for one first campaign, never a send. Uplift turns the answers into a draft campaign in the
-- CRM's Marketing area, where the client still sees the exact recipients and message and presses approve
-- (plan §3.9; docs/marketing-product-blueprint.md). Paid advertising is not part of this service, so nothing
-- here asks about ad accounts or budgets.
--
-- The answers match what the CRM's campaigns can already do, so Uplift copies them across: the goals
-- (src/lib/marketing/campaign-content.ts), the customer-group rules — service, town, last finished job, work
-- already booked (src/lib/marketing/customer-groups.ts) — and the button that calls, opens a request form or the
-- website. People who unsubscribed or never agreed are always left out by the CRM itself, so they are not a
-- choice. Text campaigns are an approved later part of Marketing; the channel question appears only with Calls
-- and texting, and until text campaigns and the sender are ready the campaign is drafted as an email.
--
-- Facts given in earlier stages are confirmed, not typed again: the business name the campaign comes from and who
-- hears about new enquiries. Services and places are picked from the lists in Services and service area. Where
-- the contacts came from and what they agreed to is asked as plain facts, separately for email and texts; Uplift
-- works out which country's rule applies instead of asking the client legal questions.

select private.setup_load_starter_stage(
	'marketing',
	'Marketing campaigns',
	'What your first campaign to past customers should achieve. Uplift prepares it as a draft — nothing is sent until you approve it.',
	'marketing',
	$items$[
		{"type": "heading", "label": "What the campaign is for",
			"hint": "Campaigns go to people who already know your business — past customers and people who asked you for a quote."},
		{"type": "question", "fact_key": "marketing.goal", "kind": "choice", "allow_other": true, "required": true,
			"label": "What should your first campaign achieve?",
			"options": [
				{"value": "repeat_work", "label": "Bring past customers back for more work"},
				{"value": "referrals", "label": "Ask past customers to recommend you to friends"},
				{"value": "seasonal", "label": "Fill the diary before a busy season"},
				{"value": "promote_service", "label": "Tell customers about one service"},
				{"value": "fill_gaps", "label": "Fill quiet weeks or cancelled slots"}
			]},
		{"type": "question", "fact_key": "marketing.services", "kind": "pick", "pick_from": "services.offered",
			"max_choices": 3, "ordered": true, "required": true,
			"label": "Which services should it promote?",
			"hint": "Up to 3, most important first."},
		{"type": "question", "fact_key": "marketing.places", "kind": "pick", "pick_from": "area.places",
			"max_choices": 10,
			"label": "Should it only go to customers in certain places?",
			"hint": "Optional. Leave it empty to include everywhere you work."},

		{"type": "heading", "label": "Who receives it",
			"hint": "Anyone who unsubscribed, asked not to be contacted, or never agreed to marketing is always left out — you don’t need to list them."},
		{"type": "question", "fact_key": "marketing.audience", "kind": "choice", "required": true,
			"label": "Who should receive it?",
			"options": [
				{"value": "past_customers", "label": "Customers I have done work for"},
				{"value": "quoted_not_booked", "label": "People I quoted who didn’t book"},
				{"value": "crm_group", "label": "One group of customers, like one town or one service"},
				{"value": "own_list", "label": "A list of people who agreed to hear from me"}
			]},
		{"type": "question", "fact_key": "marketing.audience_note", "kind": "longtext", "max_length": 1000,
			"label": "Describe them in your own words.",
			"hint": "Optional. For example: “everyone who had a boiler service more than a year ago”."},
		{"type": "question", "fact_key": "marketing.exclusions", "kind": "multi_choice", "max_choices": 6,
			"allow_other": true, "required": true,
			"label": "Who else should be left out?",
			"options": [
				{"value": "complaint", "label": "Customers with an open complaint or problem"},
				{"value": "recent", "label": "Customers who had work done recently"},
				{"value": "booked", "label": "Customers who already have work booked"},
				{"value": "outside_area", "label": "People outside the places chosen above"},
				{"value": "wrong_service", "label": "People the service doesn’t suit"},
				{"value": "nobody_else", "label": "Nobody else"}
			]},
		{"type": "question", "fact_key": "marketing.sources", "kind": "multi_choice", "max_choices": 3,
			"allow_other": true, "required": true,
			"label": "Where are these people’s details now?",
			"options": [
				{"value": "crm", "label": "In my CRM, or going into it with my other data"},
				{"value": "upload", "label": "In a list I will upload"},
				{"value": "form_or_event", "label": "They signed up on a form or at an event"}
			]},
		{"type": "question", "fact_key": "marketing.list", "kind": "protected_file", "max_files": 5,
			"required": true, "can_defer": true,
			"label": "Upload the list.",
			"hint": "A spreadsheet with each person’s name and email or phone. Only the business owner and Uplift can open it.",
			"show_if": [{"fact_key": "marketing.sources", "values": ["upload"]}]},

		{"type": "heading", "label": "Permission to contact them",
			"hint": "Marketing rules depend on where each person lives. Give the plain facts — Uplift checks which rules apply, and leaves out anyone who can’t be contacted."},
		{"type": "question", "fact_key": "marketing.email_permission", "kind": "choice", "required": true,
			"can_defer": true,
			"label": "How did these people agree to get emails from you?",
			"options": [
				{"value": "customer_could_refuse", "label": "They hired me or asked for a quote, and were offered a way to say no"},
				{"value": "said_yes", "label": "They ticked a box or said yes to hearing from me"},
				{"value": "mixed", "label": "Some one way, some the other"},
				{"value": "not_sure", "label": "I’m not sure"}
			]},
		{"type": "question", "fact_key": "marketing.permission_story", "kind": "longtext", "max_length": 1500,
			"required": true, "can_defer": true,
			"label": "What were they told when you got their details, and roughly when?",
			"hint": "For example: “our quote form says we send a few offers a year — customers since 2022”."},
		{"type": "question", "fact_key": "marketing.permission_proof", "kind": "protected_file", "max_files": 5,
			"label": "Upload any proof you have.",
			"hint": "Optional. A screenshot of the form, a sign-up sheet or similar. Only the business owner and Uplift can open it."},
		{"type": "question", "fact_key": "marketing.has_opt_out_list", "kind": "yes_no", "required": true,
			"label": "Do you keep a list of people who asked not to get marketing from you?",
			"hint": "Include any list from another email or text tool you used before."},
		{"type": "question", "fact_key": "marketing.opt_out_list", "kind": "protected_file", "max_files": 5,
			"required": true, "can_defer": true,
			"label": "Upload that list.",
			"hint": "Everyone on it is left out of every campaign. Only the business owner and Uplift can open it.",
			"show_if": [{"fact_key": "marketing.has_opt_out_list", "values": ["yes"]}]},

		{"type": "heading", "label": "The offer and how much work you can take",
			"hint": "So the campaign never promises more than you can deliver."},
		{"type": "question", "fact_key": "marketing.has_offer", "kind": "yes_no", "required": true,
			"label": "Is there a special offer?"},
		{"type": "question", "fact_key": "marketing.offer", "kind": "longtext", "max_length": 1000, "required": true,
			"label": "Describe the offer exactly.",
			"hint": "What it is worth, who can have it, what it doesn’t cover, when it ends, and how customers claim it.",
			"show_if": [{"fact_key": "marketing.has_offer", "values": ["yes"]}]},
		{"type": "question", "fact_key": "marketing.capacity", "kind": "number", "required": true,
			"label": "About how many extra jobs could you take on from this campaign?",
			"hint": "A rough number is fine. Uplift sizes the campaign so you aren’t flooded."},
		{"type": "question", "fact_key": "marketing.capacity_note", "kind": "longtext", "max_length": 500,
			"label": "Anything that limits it?",
			"hint": "Optional. For example: “away 1–14 August” or “stop once March is full”."},

		{"type": "heading", "label": "How and when it goes out",
			"hint": "Before anything is scheduled, you see the exact message and who receives it. Never at night where the customer lives."},
		{"type": "question", "fact_key": "marketing.channel", "kind": "choice", "required": true,
			"label": "How should it be sent?",
			"hint": "Text campaigns start once your texting registration is approved and Uplift switches them on for you; until then it is prepared as an email.",
			"show_if": [{"service_key": "calls_texting"}],
			"options": [
				{"value": "email", "label": "By email (recommended)"},
				{"value": "text", "label": "By text"},
				{"value": "both", "label": "Both"}
			]},
		{"type": "question", "fact_key": "marketing.text_permission", "kind": "choice", "required": true,
			"can_defer": true,
			"label": "How did these people agree to get texts from you?",
			"hint": "Texting rules are stricter than email: usually a clear yes to marketing texts is needed.",
			"show_if": [{"service_key": "calls_texting"}, {"fact_key": "marketing.channel", "values": ["text", "both"]}],
			"options": [
				{"value": "said_yes_texts", "label": "They said yes to marketing texts, for example by ticking a box"},
				{"value": "customer_only", "label": "They are customers, but never agreed to marketing texts"},
				{"value": "not_sure", "label": "I’m not sure"}
			]},
		{"type": "question", "fact_key": "marketing.start_date", "kind": "date", "required": true, "can_defer": true,
			"label": "When should the campaign go out?",
			"hint": "The earliest date that suits you. Uplift agrees the exact day and time with you before scheduling."},
		{"type": "question", "fact_key": "marketing.end_date", "kind": "date",
			"label": "Is there a date by which it must be finished?",
			"hint": "Optional. For example, when the offer ends."},
		{"type": "question", "fact_key": "marketing.follow_up", "kind": "choice", "required": true,
			"label": "Should there be one reminder?",
			"hint": "A reminder never goes to anyone who replied, booked or unsubscribed.",
			"options": [
				{"value": "none", "label": "No, just the one message"},
				{"value": "one", "label": "Yes, one reminder a few days later"}
			]},

		{"type": "heading", "label": "What it says",
			"hint": "Uplift writes the message; you see and approve every word."},
		{"type": "question", "fact_key": "marketing.sender_name", "kind": "reuse", "reuse_from": "business.public_name",
			"required": true,
			"label": "Which business name should it come from?",
			"hint": "Marketing emails also show your business address from Your business at the bottom — the law requires it in many countries."},
		{"type": "question", "fact_key": "marketing.reply_people", "kind": "reuse", "reuse_from": "website.form_recipients",
			"required": true,
			"label": "Who should handle replies and new enquiries from it?",
			"hint": "Every reply and enquiry also lands in your CRM."},
		{"type": "question", "fact_key": "marketing.action", "kind": "choice", "required": true,
			"label": "What should people do next?",
			"options": [
				{"value": "request", "label": "Ask for a quote online (recommended — it lands in your CRM)"},
				{"value": "book", "label": "Book online"},
				{"value": "call", "label": "Call you"},
				{"value": "reply", "label": "Reply to the message"},
				{"value": "website_page", "label": "Visit a page on your website"}
			]},
		{"type": "question", "fact_key": "marketing.action_link", "kind": "url", "required": true, "can_defer": true,
			"label": "Which page should it link to?",
			"hint": "If Uplift is building your website, choose “I need Uplift’s help” and Uplift adds it.",
			"show_if": [{"fact_key": "marketing.action", "values": ["website_page"]}]},
		{"type": "question", "fact_key": "marketing.tone", "kind": "choice",
			"label": "How should it sound?",
			"hint": "Optional.",
			"options": [
				{"value": "recommended", "label": "Use Uplift’s recommended wording"},
				{"value": "friendly", "label": "Warm and friendly"},
				{"value": "professional", "label": "Polite and formal"},
				{"value": "short", "label": "Short and to the point"},
				{"value": "timely", "label": "Timely but honest, like “slots are filling up”"}
			]},
		{"type": "question", "fact_key": "marketing.must_include", "kind": "longtext", "max_length": 2000,
			"can_defer": true,
			"label": "Any wording Uplift must use, or must avoid?",
			"hint": "Optional. For example, the exact terms of an offer, or words your trade body doesn’t allow."},
		{"type": "question", "fact_key": "marketing.files", "kind": "file", "file_kinds": ["photo", "document"],
			"max_files": 5,
			"label": "Any photos or documents it should use?",
			"hint": "Optional. Only photos you own or have permission to use."},

		{"type": "heading", "label": "Nothing sends from setup",
			"hint": "Sending setup to Uplift never sends a campaign."},
		{"type": "question", "fact_key": "marketing.draft_only", "kind": "yes_no", "required": true,
			"label": "Do you agree that Uplift prepares this as a draft, and nothing is sent until you approve who receives it and the exact message?"}
	]$items$::jsonb
);
