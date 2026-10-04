-- Client onboarding B5: the approved starter content's stage 3, "Brand, photos and proof"
-- (docs/client-onboarding-setup-content-blueprint.md), loaded into the setup draft for Jafar to review and
-- publish. Nothing a client sees changes until he publishes it. The stage is new, so no answer is affected.
--
-- Missing branding never blocks: "no logo", "someone else has it" and "I need Uplift's help" are all answers,
-- and photos start with a plain yes/no so a client with none is not asked to tick kinds of photo. Every
-- uploaded logo and photo carries the client's own word on whether they may publish it (plan §3.3), and each
-- photo whether it shows a customer, child, address, number plate or private place. One upload question takes
-- brand guides, brochures, price sheets and old website files, so a client has one place to put them.

select private.setup_load_starter_stage(
	'brand',
	'Brand, photos and proof',
	'How your business looks and why customers trust it — used on your website, Google profile and campaigns.',
	null,
	$items$[
		{"type": "heading", "label": "Look and feel",
			"hint": "Nothing here is required to get started. Uplift works with whatever you have."},
		{"type": "question", "fact_key": "brand.logo_status", "kind": "choice", "required": true,
			"label": "Do you already have a logo?",
			"hint": "No logo is fine — setup never waits for one. If your package includes a website, Uplift makes a simple name-and-colours logo that you own.",
			"options": [
				{"value": "upload", "label": "Yes, I can upload it"},
				{"value": "someone_else", "label": "Yes, but someone else has the files"},
				{"value": "need_help", "label": "I need Uplift’s help"},
				{"value": "none", "label": "No logo yet"}
			]},
		{"type": "question", "fact_key": "brand.logo_files", "kind": "file", "file_kinds": ["photo", "document"],
			"max_files": 5, "required": true, "can_defer": true,
			"label": "Upload the best logo files you have.",
			"hint": "A PNG with a see-through background or a PDF is best. Add light and dark versions if you have them.",
			"show_if": [{"fact_key": "brand.logo_status", "values": ["upload"]}]},
		{"type": "question", "fact_key": "brand.logo_owned", "kind": "yes_no", "required": true,
			"label": "Does the business own this logo, or have permission to use it?",
			"hint": "If you are not sure, answer No — Uplift checks with you before using it anywhere.",
			"show_if": [{"fact_key": "brand.logo_status", "values": ["upload"]}]},
		{"type": "question", "fact_key": "brand.logo_holder", "kind": "text", "required": true, "can_defer": true,
			"label": "Who has the logo files?",
			"hint": "For example your designer, printer or old website company.",
			"show_if": [{"fact_key": "brand.logo_status", "values": ["someone_else"]}]},
		{"type": "question", "fact_key": "brand.colours", "kind": "colours",
			"label": "Which colours are already part of your brand?",
			"hint": "Optional. Pick them, or type the codes if you know them."},
		{"type": "question", "fact_key": "brand.style_rules", "kind": "longtext",
			"label": "Are there fonts or style rules Uplift must keep?",
			"hint": "Optional. If you have a brand guide, upload it in the next question."},
		{"type": "question", "fact_key": "brand.existing_files", "kind": "file", "file_kinds": ["photo", "document"],
			"max_files": 10,
			"label": "Upload any brand guide, brochure, price sheet or old website files Uplift can use.",
			"hint": "Optional."},
		{"type": "question", "fact_key": "brand.feel", "kind": "multi_choice", "max_choices": 3,
			"allow_other": true,
			"label": "Which words should your business feel like?",
			"hint": "Optional. Tick up to 3.",
			"options": [
				{"value": "dependable", "label": "Dependable"},
				{"value": "premium", "label": "Premium"},
				{"value": "friendly", "label": "Friendly"},
				{"value": "fast", "label": "Fast"},
				{"value": "traditional", "label": "Traditional"},
				{"value": "modern", "label": "Modern"}
			]},
		{"type": "question", "fact_key": "brand.avoid", "kind": "longtext",
			"label": "Is there anything your brand must never look or sound like?",
			"hint": "Optional. For example “not flashy” or “no cartoon characters”."},

		{"type": "heading", "label": "Photos and examples",
			"hint": "Real photos win more work than stock images. Add what you have now; more can come later."},
		{"type": "question", "fact_key": "photos.have", "kind": "yes_no", "required": true,
			"label": "Do you have real photos Uplift can use?",
			"hint": "Photos of your own work, team, vans or premises. No is fine — you can add some later."},
		{"type": "question", "fact_key": "photos.kinds", "kind": "multi_choice", "required": true,
			"label": "What do your photos show?",
			"show_if": [{"fact_key": "photos.have", "values": ["yes"]}],
			"options": [
				{"value": "completed_work", "label": "Finished jobs"},
				{"value": "before_after", "label": "Before and after"},
				{"value": "team", "label": "You or your team"},
				{"value": "vehicles", "label": "Vans or vehicles"},
				{"value": "premises", "label": "Office, yard or showroom"},
				{"value": "equipment", "label": "Equipment"}
			]},
		{"type": "question", "fact_key": "photos.uploads", "kind": "list", "max_rows": 20, "required": true,
			"can_defer": true,
			"label": "Upload your best photos and say what each one shows.",
			"hint": "Up to 20. Uplift checks with you before using any photo that shows private details or that you may not publish.",
			"show_if": [{"fact_key": "photos.have", "values": ["yes"]}],
			"list_fields": [
				{"key": "photo", "label": "Photo", "kind": "file", "required": true, "file_kinds": ["photo"]},
				{"key": "caption", "label": "What it shows", "kind": "text", "required": true},
				{"key": "private_details", "label": "Does it show a customer, child, home address, number plate or private place?",
					"kind": "yes_no", "required": true},
				{"key": "may_publish", "label": "Did you take it, or do you have permission to publish it?",
					"kind": "yes_no", "required": true}
			]},
		{"type": "question", "fact_key": "photos.inspiration", "kind": "list", "max_rows": 3,
			"label": "Share up to three websites or brands you like.",
			"hint": "Optional, and only for ideas — Uplift never copies another business.",
			"list_fields": [
				{"key": "url", "label": "Website", "kind": "url", "required": true},
				{"key": "note", "label": "What you like about it", "kind": "text", "required": false}
			]},

		{"type": "heading", "label": "Trust and proof",
			"hint": "Facts customers can check. Uplift publishes only what you give here."},
		{"type": "question", "fact_key": "proof.years", "kind": "number",
			"label": "How many years has the business been operating?",
			"hint": "Optional."},
		{"type": "question", "fact_key": "proof.items", "kind": "list", "max_rows": 10,
			"label": "Add awards, memberships, accreditations or insurance customers may see.",
			"hint": "Optional. Add the number only if it may be shown publicly.",
			"list_fields": [
				{"key": "name", "label": "Name", "kind": "text", "required": true},
				{"key": "issuer", "label": "Given by", "kind": "text", "required": false},
				{"key": "number", "label": "Number, if public", "kind": "text", "required": false},
				{"key": "expires_on", "label": "Expiry date, if any", "kind": "date", "required": false},
				{"key": "file", "label": "Copy or certificate", "kind": "file", "required": false,
					"file_kinds": ["document", "photo"]}
			]},
		{"type": "question", "fact_key": "proof.guarantees", "kind": "list", "max_rows": 5,
			"label": "What guarantees or warranties do you actually offer?",
			"hint": "Optional. Say how long each lasts and any limits.",
			"list_fields": [
				{"key": "text", "label": "Guarantee or warranty", "kind": "longtext", "required": true}
			]},
		{"type": "question", "fact_key": "proof.payment_methods", "kind": "multi_choice", "required": true,
			"allow_other": true,
			"label": "How can customers pay you today?",
			"hint": "Tick every way you accept now. This does not switch on online payments.",
			"options": [
				{"value": "cash", "label": "Cash"},
				{"value": "cheque", "label": "Cheque"},
				{"value": "bank_transfer", "label": "Bank transfer"},
				{"value": "card", "label": "Debit or credit card"}
			]},
		{"type": "question", "fact_key": "proof.financing", "kind": "yes_no", "required": true,
			"label": "Do you offer financing to customers?"},
		{"type": "question", "fact_key": "proof.financing_details", "kind": "longtext", "required": true,
			"can_defer": true,
			"label": "Describe the financing.",
			"hint": "The provider’s name and who qualifies, in the provider’s own wording.",
			"show_if": [{"fact_key": "proof.financing", "values": ["yes"]}]},
		{"type": "question", "fact_key": "proof.reasons", "kind": "list", "max_rows": 10, "required": true,
			"label": "Why do customers choose you?",
			"hint": "Facts, one per row — for example “We reply within 2 hours”, “All work guaranteed for 5 years” or “20 years in the area”.",
			"list_fields": [
				{"key": "reason", "label": "Reason", "kind": "text", "required": true}
			]},
		{"type": "question", "fact_key": "proof.testimonials", "kind": "list", "max_rows": 10,
			"label": "Add customer reviews Uplift may publish.",
			"hint": "Optional. Real words from real customers only — Uplift never edits or invents them.",
			"list_fields": [
				{"key": "quote", "label": "What they said", "kind": "longtext", "required": true},
				{"key": "name", "label": "Name to show, for example “Sarah, Leeds”", "kind": "text", "required": true},
				{"key": "permission", "label": "Did the customer agree to be quoted?", "kind": "yes_no", "required": true},
				{"key": "source", "label": "Where it came from, for example Google or a text", "kind": "text", "required": false},
				{"key": "date", "label": "Date", "kind": "date", "required": false},
				{"key": "proof", "label": "Screenshot or copy", "kind": "file", "required": false,
					"file_kinds": ["photo", "document"]}
			]},
		{"type": "question", "fact_key": "proof.social", "kind": "list", "max_rows": 10,
			"label": "Add your business’s social media pages.",
			"hint": "Optional. Just the public link — Uplift never asks for a password.",
			"list_fields": [
				{"key": "platform", "label": "Platform", "kind": "choice", "required": true,
					"options": [
						{"value": "facebook", "label": "Facebook"},
						{"value": "instagram", "label": "Instagram"},
						{"value": "youtube", "label": "YouTube"},
						{"value": "tiktok", "label": "TikTok"},
						{"value": "linkedin", "label": "LinkedIn"},
						{"value": "x", "label": "X (Twitter)"},
						{"value": "nextdoor", "label": "Nextdoor"},
						{"value": "other", "label": "Other"}
					]},
				{"key": "url", "label": "Link", "kind": "url", "required": true}
			]}
	]$items$::jsonb
);
