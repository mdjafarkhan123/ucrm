-- Client onboarding B7: the approved starter content's stage 7, "Google Business Profile"
-- (docs/client-onboarding-setup-content-blueprint.md), loaded into the setup draft for Jafar to review and
-- publish. Nothing a client sees changes until he publishes it. The stage is new, so no answer is affected, and
-- it is shown only to a client whose package includes Google Business Profile management.
--
-- The contractor stays the profile's owner and adds Uplift as a manager; no Google password is ever asked
-- (plan §3.5). A new profile is made in the contractor's own Google account.
--
-- Facts given in earlier stages are confirmed, not typed again: the public name, phone, opening date and
-- service areas are reused. The address and hours are asked only on some answers in Your business, so they
-- cannot be shown back; a yes/no confirms them instead, with a fresh answer only on No. Google decides whether
-- an address is shown — only when customers visit it — so the storefront/service-area choice settles that
-- rather than a separate question. Google categories are proposed by Uplift later and approved by the client
-- before publishing; they are not a setup question.

select private.setup_load_starter_stage(
	'google',
	'Google Business Profile',
	'The facts behind your listing on Google Search and Maps — so Uplift can set it up accurately. It stays yours.',
	'google_profile',
	$items$[
		{"type": "heading", "label": "Your Google profile",
			"hint": "The listing customers see when they search for you on Google or Maps. It always belongs to you. Uplift never asks for your Google password."},
		{"type": "question", "fact_key": "gbp.situation", "kind": "choice", "required": true,
			"label": "Do you already have a Google Business Profile?",
			"options": [
				{"value": "own", "label": "Yes, I own or manage it"},
				{"value": "someone_else", "label": "Yes, but someone else controls it"},
				{"value": "need_new", "label": "No, I need a new one"},
				{"value": "unsure", "label": "I’m not sure"}
			]},
		{"type": "question", "fact_key": "gbp.link", "kind": "url",
			"label": "Paste the link to your profile.",
			"hint": "Optional. Find your business on Google Maps, tap Share, and copy the link.",
			"show_if": [{"fact_key": "gbp.situation", "values": ["own", "someone_else", "unsure"]}]},
		{"type": "question", "fact_key": "gbp.controller", "kind": "list", "max_rows": 1, "required": true,
			"can_defer": true,
			"label": "Who controls it today?",
			"hint": "For example a former marketing company or an old employee. The profile still belongs to your business.",
			"show_if": [{"fact_key": "gbp.situation", "values": ["someone_else"]}],
			"list_fields": [
				{"key": "name", "label": "Name", "kind": "text", "required": true},
				{"key": "company", "label": "Company", "kind": "text", "required": false},
				{"key": "email", "label": "Email", "kind": "email", "required": false},
				{"key": "phone", "label": "Phone", "kind": "phone", "required": false}
			]},
		{"type": "question", "fact_key": "gbp.owner_account", "kind": "email", "required": true, "can_defer": true,
			"label": "Which Google account should own the new profile?",
			"hint": "Use an account your business controls, such as the one for your business email. The profile belongs to that account; Uplift is added as a manager.",
			"show_if": [{"fact_key": "gbp.situation", "values": ["need_new"]}]},

		{"type": "heading", "label": "What Google shows",
			"hint": "Google suspends profiles whose details don’t match the real business, so plain facts matter here. Uplift also suggests your Google categories from your trade and services, and shows them to you before anything is published."},
		{"type": "question", "fact_key": "gbp.business_model", "kind": "choice", "required": true,
			"label": "Where do you serve customers?",
			"hint": "Google shows your address only if customers come to it during your hours. Otherwise it shows the areas you cover instead.",
			"options": [
				{"value": "storefront", "label": "Customers come to me — a shop, showroom or office"},
				{"value": "service_area", "label": "I go to my customers"},
				{"value": "both", "label": "Both"}
			]},
		{"type": "question", "fact_key": "gbp.public_name", "kind": "reuse", "reuse_from": "business.public_name",
			"required": true,
			"label": "Which business name should Google show?",
			"hint": "Exactly as on your van, signs and invoices. Adding words like a town or “best plumber” can get a profile suspended."},
		{"type": "question", "fact_key": "gbp.other_names", "kind": "text", "max_length": 300,
			"label": "Do customers call your work something not in your services list?",
			"hint": "Optional. For example “boiler servicing” when you listed “heating”. Real words customers use, not extra keywords."},
		{"type": "question", "fact_key": "gbp.phone", "kind": "reuse", "reuse_from": "business.public_phone",
			"required": true,
			"label": "Which phone number should Google show?"},
		{"type": "question", "fact_key": "gbp.hours_same", "kind": "yes_no", "required": true,
			"label": "Should Google show the hours you gave in Your business?"},
		{"type": "question", "fact_key": "gbp.hours", "kind": "longtext", "max_length": 1000, "required": true,
			"label": "What hours should Google show?",
			"hint": "Each day’s opening and closing time, or say if you are open around the clock.",
			"show_if": [{"fact_key": "gbp.hours_same", "values": ["no"]}]},
		{"type": "question", "fact_key": "gbp.website", "kind": "url",
			"label": "Which website should Google link to?",
			"hint": "Optional. Leave it blank if Uplift is building your new website — it is added when the website goes live."},
		{"type": "question", "fact_key": "gbp.opening_date", "kind": "reuse", "reuse_from": "business.started_on",
			"label": "When did the business open?",
			"hint": "Optional. Google shows this as your opening date."},
		{"type": "question", "fact_key": "gbp.service_areas", "kind": "reuse", "reuse_from": "area.places",
			"required": true,
			"label": "Which areas should Google show you cover?",
			"hint": "Google shows up to 20. Use a different list here if you gave more, or want fewer.",
			"show_if": [{"fact_key": "gbp.business_model", "values": ["service_area", "both"]}]},
		{"type": "question", "fact_key": "gbp.photos_ok", "kind": "yes_no", "required": true,
			"label": "May Uplift add the photos you shared to your Google profile?",
			"hint": "Only the ones you said may be published.",
			"show_if": [{"fact_key": "photos.have", "values": ["yes"]}]},
		{"type": "question", "fact_key": "gbp.photos_leave_out", "kind": "longtext", "max_length": 1000,
			"required": true,
			"label": "Which photos should stay off Google?",
			"show_if": [{"fact_key": "gbp.photos_ok", "values": ["no"]}]},

		{"type": "heading", "label": "Proving the business is real",
			"hint": "Google checks a new or changed profile — by a code in the post, a call, an email or a short video. Its timing is up to Google."},
		{"type": "question", "fact_key": "gbp.verify_same", "kind": "yes_no", "required": true,
			"label": "Can Google check your business at the address you gave in Your business?",
			"hint": "If customers don’t come to you there, Google keeps it hidden."},
		{"type": "question", "fact_key": "gbp.verify_address", "kind": "list", "max_rows": 1, "required": true,
			"can_defer": true,
			"label": "Which address should Google check instead?",
			"hint": "A real address where you get post. Google doesn’t accept a PO box or a shared desk.",
			"show_if": [{"fact_key": "gbp.verify_same", "values": ["no"]}],
			"list_fields": [
				{"key": "line1", "label": "Street address", "kind": "text", "required": true},
				{"key": "line2", "label": "Flat, unit or suite", "kind": "text", "required": false},
				{"key": "city", "label": "Town or city", "kind": "text", "required": true},
				{"key": "region", "label": "State, province or county", "kind": "text", "required": false},
				{"key": "postal_code", "label": "Postcode or ZIP code", "kind": "text", "required": true}
			]},

		{"type": "heading", "label": "Past problems",
			"hint": "These are common. Knowing early lets Uplift fix them the right way, instead of making them worse."},
		{"type": "question", "fact_key": "gbp.history", "kind": "yes_no_unsure", "required": true,
			"label": "Has a Google profile for this business ever been suspended, disabled, merged, moved or renamed?"},
		{"type": "question", "fact_key": "gbp.history_details", "kind": "longtext", "max_length": 2000,
			"required": true, "can_defer": true,
			"label": "What happened?",
			"hint": "Roughly when, and what Google said, if you remember.",
			"show_if": [{"fact_key": "gbp.history", "values": ["yes", "not_sure"]}]},
		{"type": "question", "fact_key": "gbp.history_files", "kind": "file", "file_kinds": ["document", "photo"],
			"max_files": 5,
			"label": "Upload any emails or screenshots from Google about it.",
			"hint": "Optional.",
			"show_if": [{"fact_key": "gbp.history", "values": ["yes", "not_sure"]}]},
		{"type": "question", "fact_key": "gbp.duplicates", "kind": "yes_no_unsure", "required": true,
			"label": "Is there more than one Google profile for this business or its address?",
			"hint": "For example an old one from before a move, or one a former partner made."},
		{"type": "question", "fact_key": "gbp.duplicate_list", "kind": "list", "max_rows": 10, "required": true,
			"can_defer": true,
			"label": "Share a link or screenshot of each one.",
			"show_if": [{"fact_key": "gbp.duplicates", "values": ["yes", "not_sure"]}],
			"list_fields": [
				{"key": "url", "label": "Link", "kind": "url", "required": false},
				{"key": "screenshot", "label": "Screenshot", "kind": "file", "required": false, "file_kinds": ["photo"]},
				{"key": "note", "label": "Anything you know about it", "kind": "text", "required": false}
			]},

		{"type": "heading", "label": "Access for Uplift",
			"hint": "After setup, Uplift sends you its email address and Google’s steps: open your profile, then Menu › Business Profile settings › People and access › Add, and choose Manager. You stay the owner."},
		{"type": "question", "fact_key": "gbp.manager_by", "kind": "choice", "required": true,
			"label": "Who will add Uplift as a manager?",
			"show_if": [{"fact_key": "gbp.situation", "values": ["own", "someone_else"]}],
			"options": [
				{"value": "me", "label": "I will"},
				{"value": "controller", "label": "The person who controls it now"},
				{"value": "help", "label": "I’d like Uplift to walk me through it"}
			]}
	]$items$::jsonb
);
