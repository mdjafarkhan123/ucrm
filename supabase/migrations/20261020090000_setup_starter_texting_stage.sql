-- Client onboarding B9c: the approved starter content's stage 9, "Texting registration"
-- (docs/client-onboarding-setup-content-blueprint.md), loaded into the setup draft for Jafar to review and
-- publish, and stage 8 loaded again with the bill for moving a number. Nothing a client sees changes until he
-- publishes. Both stages are shown only to a client whose package includes Calls and texting.
--
-- Jafar's decisions (2026-10-04, after comparing GoHighLevel's number-move and texting-registration flow):
-- the bill and any registration document are protected files, which only the business owner and Jafar can
-- open; no transfer PIN is asked here (Uplift asks once, when it sends the move); no signed letter is uploaded
-- (the phone network emails it to the approver to sign); a US client may add the IRS letter showing the EIN,
-- but never has to.
--
-- The questions follow what the phone networks ask for a business's texting (Twilio's A2P 10DLC brand and
-- campaign, and toll-free verification), in everyday words. The monthly ranges and consent ways match the
-- CRM's own texting registration form (src/lib/server/validation/communications-sms-registration.schema.ts),
-- so Uplift can copy the answers across. A sole trader with no registration number is allowed: in the USA and
-- Canada the networks then text a one-time code to the representative's mobile, which Uplift arranges.
--
-- Stage 8 again: unchanged except the bill question after "Whose name and address are on that phone
-- account?", and its heading no longer says the bill is asked for separately.

-- 1. Stage 8 — Calls and routing, with the bill ------------------------------------------------------------

select private.setup_load_starter_stage(
	'calls',
	'Calls and phone number',
	'Your business number and where its calls go — so customers always reach someone, or leave a message.',
	'calls_texting',
	$items$[
		{"type": "heading", "label": "Your business number",
			"hint": "The number customers call and text. Nothing goes live until you have tried a test call."},
		{"type": "question", "fact_key": "calls.number_plan", "kind": "choice", "required": true,
			"label": "Which number should customers use?",
			"hint": "If customers already know your number, keeping it is usually best.",
			"options": [
				{"value": "new", "label": "A new number from Uplift"},
				{"value": "keep", "label": "The number I already have"},
				{"value": "advice", "label": "I’m not sure — help me choose"}
			]},
		{"type": "question", "fact_key": "calls.new_number_area", "kind": "text", "max_length": 120,
			"required": true, "can_defer": true,
			"label": "Which town or area should the new number belong to?",
			"hint": "Uplift looks for a local number there. Which numbers are free is up to the phone network.",
			"show_if": [{"fact_key": "calls.number_plan", "values": ["new"]}]},
		{"type": "question", "fact_key": "calls.existing_number", "kind": "phone", "required": true,
			"can_defer": true,
			"label": "Which number do you want to keep?",
			"show_if": [{"fact_key": "calls.number_plan", "values": ["keep"]}]},
		{"type": "question", "fact_key": "calls.keep_how", "kind": "choice", "required": true,
			"label": "How should Uplift use it?",
			"hint": "Forwarding is quick and easy to undo; texts then usually come from a second Uplift number. Moving it can take a few weeks, and Uplift first checks your phone company allows it.",
			"show_if": [{"fact_key": "calls.number_plan", "values": ["keep"]}],
			"options": [
				{"value": "forward", "label": "Forward its calls — it stays with my phone company"},
				{"value": "move", "label": "Move it to Uplift completely"},
				{"value": "unsure", "label": "I’m not sure"}
			]},
		{"type": "question", "fact_key": "calls.text_from_existing", "kind": "yes_no_unsure", "required": true,
			"label": "Should customers get texts from this same number?",
			"hint": "In the USA and Canada, Uplift can usually add texting to a landline or toll-free number while its calls stay where they are. Mobile numbers can’t.",
			"show_if": [
				{"fact_key": "calls.keep_how", "values": ["forward", "unsure"]},
				{"fact_key": "business.country", "values": ["US", "CA"]}
			]},

		{"type": "heading", "label": "Moving your number",
			"hint": "Your phone company has to agree, and the details must match its records exactly. Keep your current phone service until the move is finished. If your phone company uses a transfer PIN, Uplift asks for it separately when it sends the request."},
		{"type": "question", "fact_key": "calls.port_carrier", "kind": "text", "max_length": 120,
			"required": true, "can_defer": true,
			"label": "Which phone company is the number with now?",
			"show_if": [{"fact_key": "calls.keep_how", "values": ["move"]}]},
		{"type": "question", "fact_key": "calls.port_account", "kind": "list", "max_rows": 1, "required": true,
			"can_defer": true,
			"label": "Whose name and address are on that phone account?",
			"hint": "Exactly as on the bill. A small difference is the most common reason a move is turned down.",
			"show_if": [{"fact_key": "calls.keep_how", "values": ["move"]}],
			"list_fields": [
				{"key": "name", "label": "Account holder", "kind": "text", "required": true},
				{"key": "company", "label": "Business name on the account", "kind": "text", "required": false},
				{"key": "line1", "label": "Street address", "kind": "text", "required": true},
				{"key": "line2", "label": "Flat, unit or suite", "kind": "text", "required": false},
				{"key": "city", "label": "Town or city", "kind": "text", "required": true},
				{"key": "region", "label": "State, province or county", "kind": "text", "required": false},
				{"key": "postal_code", "label": "Postcode or ZIP code", "kind": "text", "required": true}
			]},
		{"type": "question", "fact_key": "calls.port_bill", "kind": "protected_file", "max_files": 5,
			"required": true, "can_defer": true,
			"label": "Upload a recent bill for that number.",
			"hint": "A bill from the last month or two that shows the number, the account holder and the address. Only the business owner and Uplift can open it, and it is deleted after the move.",
			"show_if": [{"fact_key": "calls.keep_how", "values": ["move"]}]},
		{"type": "question", "fact_key": "calls.port_approver", "kind": "list", "max_rows": 1, "required": true,
			"label": "Who can approve the move?",
			"hint": "The account holder, or someone allowed to act for them. Uplift sends them the transfer form to sign.",
			"show_if": [{"fact_key": "calls.keep_how", "values": ["move"]}],
			"list_fields": [
				{"key": "name", "label": "Name", "kind": "text", "required": true},
				{"key": "role", "label": "Role", "kind": "text", "required": false},
				{"key": "email", "label": "Email", "kind": "email", "required": true},
				{"key": "phone", "label": "Phone", "kind": "phone", "required": false}
			]},

		{"type": "heading", "label": "Who answers",
			"hint": "Calls ring on the phones you choose. Customers only ever see your business number, never these."},
		{"type": "question", "fact_key": "calls.ring_people", "kind": "list", "max_rows": 10, "required": true,
			"can_defer": true,
			"label": "Which phones should ring when a customer calls?",
			"list_fields": [
				{"key": "name", "label": "Whose phone", "kind": "text", "required": true},
				{"key": "phone", "label": "Phone number", "kind": "phone", "required": true}
			]},
		{"type": "question", "fact_key": "calls.ring_mode", "kind": "choice", "required": true,
			"label": "Should they ring all at once, or one after another?",
			"options": [
				{"value": "together", "label": "All at once — whoever picks up first takes it"},
				{"value": "in_order", "label": "One after another, in order"}
			]},
		{"type": "question", "fact_key": "calls.ring_order", "kind": "pick", "pick_from": "calls.ring_people",
			"min_choices": 10, "ordered": true, "required": true,
			"label": "Put the phones in the order they should ring.",
			"show_if": [{"fact_key": "calls.ring_mode", "values": ["in_order"]}]},
		{"type": "question", "fact_key": "calls.ring_time", "kind": "choice", "required": true,
			"label": "How long should a phone ring before the call moves on?",
			"hint": "Much longer than 20 seconds and a mobile’s own voicemail may answer first, or the caller hangs up.",
			"options": [
				{"value": "15", "label": "15 seconds — about 3 rings"},
				{"value": "20", "label": "20 seconds — about 4 rings (recommended)"},
				{"value": "30", "label": "30 seconds — about 6 rings"}
			]},

		{"type": "heading", "label": "When nobody can answer",
			"hint": "Every call should end with a person or a message, never a caller left ringing."},
		{"type": "question", "fact_key": "calls.no_answer", "kind": "choice", "allow_other": true,
			"required": true,
			"label": "If nobody answers during your hours, what should happen?",
			"options": [
				{"value": "voicemail", "label": "Take a voicemail"},
				{"value": "backup", "label": "Ring a backup person, then take a voicemail"}
			]},
		{"type": "question", "fact_key": "calls.backup", "kind": "list", "max_rows": 1, "required": true,
			"can_defer": true,
			"label": "Who is the backup person?",
			"show_if": [{"fact_key": "calls.no_answer", "values": ["backup"]}],
			"list_fields": [
				{"key": "name", "label": "Name", "kind": "text", "required": true},
				{"key": "phone", "label": "Phone number", "kind": "phone", "required": true}
			]},
		{"type": "question", "fact_key": "calls.busy", "kind": "choice", "required": true,
			"label": "If everyone is already on a call, what should happen?",
			"options": [
				{"value": "same", "label": "The same as when nobody answers (recommended)"},
				{"value": "voicemail", "label": "Go straight to voicemail"}
			]},
		{"type": "question", "fact_key": "calls.hours_same", "kind": "yes_no", "required": true,
			"label": "Should calls ring through during the hours you gave in Your business?",
			"hint": "Outside these hours, calls follow your after-hours choice below."},
		{"type": "question", "fact_key": "calls.hours", "kind": "longtext", "max_length": 1000, "required": true,
			"label": "When should calls ring through?",
			"hint": "Each day’s start and finish time — for example, ringing until 7pm even though the office closes at 5.",
			"show_if": [{"fact_key": "calls.hours_same", "values": ["no"]}]},
		{"type": "question", "fact_key": "calls.after_hours", "kind": "choice", "allow_other": true,
			"required": true,
			"label": "What should happen to calls outside those hours?",
			"hint": "If you answer around the clock, choose “Ring as normal”.",
			"options": [
				{"value": "voicemail", "label": "Take a voicemail"},
				{"value": "emergency", "label": "Let callers press 1 for an emergency, which rings an on-call phone"},
				{"value": "ring", "label": "Ring as normal"}
			]},
		{"type": "question", "fact_key": "calls.emergency_phone", "kind": "list", "max_rows": 1, "required": true,
			"can_defer": true,
			"label": "Whose phone rings for an emergency?",
			"hint": "If they don’t answer, the caller can leave a voicemail.",
			"show_if": [{"fact_key": "calls.after_hours", "values": ["emergency"]}],
			"list_fields": [
				{"key": "name", "label": "Name", "kind": "text", "required": true},
				{"key": "phone", "label": "Phone number", "kind": "phone", "required": true}
			]},
		{"type": "question", "fact_key": "calls.language", "kind": "reuse", "reuse_from": "business.language",
			"required": true,
			"label": "Which language should callers hear?",
			"hint": "Your greeting, voicemail and the press-1 menu use it."},

		{"type": "heading", "label": "Voicemail",
			"hint": "Callers hear a short greeting, then leave their name, number and what they need."},
		{"type": "question", "fact_key": "calls.voicemail_type", "kind": "choice", "required": true,
			"label": "What greeting should callers hear before leaving a message?",
			"options": [
				{"value": "standard", "label": "Uplift’s standard greeting with my business name"},
				{"value": "write", "label": "My own words, read out by a clear computer voice"},
				{"value": "upload", "label": "A recording of my own voice"}
			]},
		{"type": "question", "fact_key": "calls.voicemail_words", "kind": "longtext", "max_length": 1000,
			"required": true, "can_defer": true,
			"label": "What should the greeting say?",
			"hint": "For example: “Thanks for calling. We’re out on a job — leave your name, number and what you need, and we’ll call you back today.”",
			"show_if": [{"fact_key": "calls.voicemail_type", "values": ["write"]}]},
		{"type": "question", "fact_key": "calls.voicemail_recording", "kind": "file", "file_kinds": ["audio"],
			"max_files": 1, "required": true, "can_defer": true,
			"label": "Upload your greeting.",
			"hint": "Under a minute, recorded somewhere quiet. Say your business name.",
			"show_if": [{"fact_key": "calls.voicemail_type", "values": ["upload"]}]},

		{"type": "heading", "label": "Alerts and missed-call texts",
			"hint": "So a missed customer is followed up quickly, not found hours later."},
		{"type": "question", "fact_key": "calls.alert_people", "kind": "list", "max_rows": 10, "required": true,
			"label": "Who should be told about missed calls, voicemails and text replies?",
			"hint": "Uplift sets up how each person is told.",
			"list_fields": [
				{"key": "name", "label": "Name", "kind": "text", "required": true},
				{"key": "email", "label": "Email", "kind": "email", "required": false},
				{"key": "phone", "label": "Mobile", "kind": "phone", "required": false}
			]},
		{"type": "question", "fact_key": "calls.missed_text", "kind": "yes_no", "required": true,
			"label": "When you miss a call, should the caller get a text back?",
			"hint": "It lets them know you’ll call back, so they don’t ring someone else. It starts only once your texting is registered and approved, which takes a few weeks."},
		{"type": "question", "fact_key": "calls.missed_text_words", "kind": "longtext", "max_length": 320,
			"required": true, "can_defer": true,
			"label": "What should that text say?",
			"hint": "Keep it short, for example: “Sorry we missed your call — we’re on a job and will ring you back within the hour.” Uplift adds your business name and how to stop texts.",
			"show_if": [{"fact_key": "calls.missed_text", "values": ["yes"]}]},

		{"type": "heading", "label": "Test call",
			"hint": "Before customers rely on it, Uplift rings through the new setup with you and checks every route."},
		{"type": "question", "fact_key": "calls.test_person", "kind": "list", "max_rows": 1, "required": true,
			"can_defer": true,
			"label": "Who should take the test call, and when suits them?",
			"list_fields": [
				{"key": "name", "label": "Name", "kind": "text", "required": true},
				{"key": "phone", "label": "Phone number", "kind": "phone", "required": true},
				{"key": "when", "label": "Best days and times", "kind": "text", "required": false}
			]}
	]$items$::jsonb
);


-- 2. Stage 9 — Texting registration ------------------------------------------------------------------------

select private.setup_load_starter_stage(
	'texting',
	'Texting registration',
	'The facts the phone networks check before your business can text customers. Texting stays off until they approve it.',
	'calls_texting',
	$items$[
		{"type": "heading", "label": "Your business, as registered",
			"hint": "The phone networks check your business against official records before it can text. Approval usually takes a few weeks."},
		{"type": "question", "fact_key": "texting.details_match", "kind": "yes_no", "required": true,
			"label": "Are the legal name, type of business and address in Your business exactly as on your official registration?",
			"hint": "A small difference — a missing “Ltd”, or an old address — is the most common reason registration is turned down."},
		{"type": "question", "fact_key": "texting.registered_details", "kind": "list", "max_rows": 1,
			"required": true,
			"label": "What does your official registration say?",
			"hint": "Copy it exactly, letter for letter.",
			"show_if": [{"fact_key": "texting.details_match", "values": ["no"]}],
			"list_fields": [
				{"key": "legal_name", "label": "Legal business name", "kind": "text", "required": true},
				{"key": "line1", "label": "Street address", "kind": "text", "required": true},
				{"key": "line2", "label": "Flat, unit or suite", "kind": "text", "required": false},
				{"key": "city", "label": "Town or city", "kind": "text", "required": true},
				{"key": "region", "label": "State, province or county", "kind": "text", "required": false},
				{"key": "postal_code", "label": "Postcode or ZIP code", "kind": "text", "required": true}
			]},
		{"type": "question", "fact_key": "texting.has_registration_number", "kind": "yes_no_unsure",
			"required": true,
			"label": "Does the business have an official registration or tax number?",
			"hint": "In the USA, an EIN. In Canada, a Business Number. In the UK, a Companies House number. In Australia, an ABN. Many sole traders don’t have one, and that’s fine."},
		{"type": "question", "fact_key": "texting.registration_number", "kind": "text", "max_length": 40,
			"required": true, "can_defer": true,
			"label": "What is that number?",
			"hint": "Exactly as on your registration or tax papers.",
			"show_if": [{"fact_key": "texting.has_registration_number", "values": ["yes"]}]},
		{"type": "question", "fact_key": "texting.registration_document", "kind": "protected_file", "max_files": 5,
			"label": "Upload the official letter or certificate that shows it.",
			"hint": "Optional. In the USA, the IRS letter with your EIN (CP-575 or 147C); elsewhere, your registration certificate. It helps when the networks question the number. Only the business owner and Uplift can open it.",
			"show_if": [{"fact_key": "texting.has_registration_number", "values": ["yes"]}]},
		{"type": "question", "fact_key": "texting.website", "kind": "url", "required": true, "can_defer": true,
			"label": "Which website shows your business?",
			"hint": "The networks check that it names your business and shows how to reach you. If Uplift is building your website, choose that you need Uplift’s help."},

		{"type": "heading", "label": "Who signs for the business",
			"hint": "The networks may contact this person to check the registration is genuine."},
		{"type": "question", "fact_key": "texting.representative", "kind": "list", "max_rows": 1, "required": true,
			"label": "Who can approve texting for the business?",
			"hint": "The owner, a director, or someone allowed to act for the business. Without a registration number, the networks text a code to this mobile to check it.",
			"list_fields": [
				{"key": "first_name", "label": "First name", "kind": "text", "required": true},
				{"key": "last_name", "label": "Last name", "kind": "text", "required": true},
				{"key": "title", "label": "Job title", "kind": "text", "required": true},
				{"key": "position", "label": "Their position", "kind": "choice", "required": true,
					"options": [
						{"value": "owner", "label": "Owner or director"},
						{"value": "ceo", "label": "Chief executive"},
						{"value": "gm", "label": "General manager"},
						{"value": "finance", "label": "Head of finance"},
						{"value": "legal", "label": "Head of legal"},
						{"value": "other", "label": "Someone else allowed to act for the business"}
					]},
				{"key": "email", "label": "Work email", "kind": "email", "required": true},
				{"key": "phone", "label": "Mobile", "kind": "phone", "required": true}
			]},
		{"type": "question", "fact_key": "texting.representative_agrees", "kind": "yes_no", "required": true,
			"label": "Has this person agreed to Uplift registering the business’s texting?",
			"hint": "If not yet, ask them before you send your setup, or name someone who has."},

		{"type": "heading", "label": "What you’ll text",
			"hint": "The networks approve the kinds of texts you describe here. Sending other kinds can get texts blocked."},
		{"type": "question", "fact_key": "texting.message_kinds", "kind": "multi_choice", "max_choices": 7,
			"required": true,
			"label": "Which texts will the business send?",
			"hint": "Offers and promotions need each customer’s separate permission, and are registered on their own.",
			"options": [
				{"value": "replies", "label": "Replies to customers who contact us"},
				{"value": "appointments", "label": "Appointment reminders and changes"},
				{"value": "quotes_invoices", "label": "Quotes, invoices and payment reminders"},
				{"value": "on_my_way", "label": "“On my way” texts"},
				{"value": "missed_calls", "label": "Texts back after a missed call"},
				{"value": "reviews", "label": "Requests for a review"},
				{"value": "marketing", "label": "Offers and promotions"}
			]},
		{"type": "question", "fact_key": "texting.recipients", "kind": "multi_choice", "max_choices": 4,
			"allow_other": true, "required": true,
			"label": "Who will get these texts?",
			"options": [
				{"value": "customers", "label": "Our customers"},
				{"value": "enquirers", "label": "People who ask us for a quote or booking"},
				{"value": "team", "label": "Our own team"}
			]},
		{"type": "question", "fact_key": "texting.monthly_volume", "kind": "choice", "required": true,
			"label": "About how many texts a month?",
			"hint": "Count every text, automatic reminders too. A rough guess is fine.",
			"options": [
				{"value": "under_500", "label": "Fewer than 500"},
				{"value": "500_2000", "label": "500 to 2,000"},
				{"value": "2001_10000", "label": "2,000 to 10,000"},
				{"value": "over_10000", "label": "More than 10,000"}
			]},
		{"type": "question", "fact_key": "texting.quiet_hours", "kind": "choice", "allow_other": true,
			"required": true,
			"label": "When may automatic texts go out?",
			"hint": "Replies you type yourself can go any time. In many places the law limits automatic texts at night.",
			"options": [
				{"value": "8_to_9", "label": "8am to 9pm in the customer’s time (recommended)"},
				{"value": "business_hours", "label": "Only during my business hours"}
			]},
		{"type": "question", "fact_key": "texting.has_links", "kind": "yes_no", "required": true,
			"label": "Will your texts include website links or phone numbers?"},
		{"type": "question", "fact_key": "texting.links", "kind": "list", "max_rows": 10, "required": true,
			"can_defer": true,
			"label": "Which websites and phone numbers?",
			"hint": "Every one a text might include. Link shorteners such as bit.ly often get texts blocked.",
			"show_if": [{"fact_key": "texting.has_links", "values": ["yes"]}],
			"list_fields": [
				{"key": "value", "label": "Website or phone number", "kind": "text", "required": true}
			]},
		{"type": "question", "fact_key": "texting.samples", "kind": "list", "max_rows": 5, "required": true,
			"can_defer": true,
			"label": "Write 2 to 5 example texts, as you would really send them.",
			"hint": "Start each with your business name. For example: “[Business name]: Hi Sam, Ali is on his way and will be with you around 2pm. Reply STOP to opt out.”",
			"list_fields": [
				{"key": "message", "label": "Example text", "kind": "longtext", "required": true}
			]},

		{"type": "heading", "label": "Permission to text",
			"hint": "Customers must agree before you text them. Uplift may suggest better wording, but never makes up proof."},
		{"type": "question", "fact_key": "texting.consent", "kind": "list", "max_rows": 5, "required": true,
			"can_defer": true,
			"label": "How do customers agree to get your texts?",
			"hint": "Add each way. Keep offers and promotions separate from texts about their work.",
			"list_fields": [
				{"key": "method", "label": "How they agree", "kind": "choice", "required": true,
					"options": [
						{"value": "website_form", "label": "A form on my website"},
						{"value": "booking_form", "label": "When they book or ask for a quote"},
						{"value": "paper_form", "label": "A paper or signed form"},
						{"value": "verbal", "label": "They say yes on a call, and we note it down"},
						{"value": "text_initiated", "label": "They text us first, or text a keyword"},
						{"value": "other", "label": "Another way"}
					]},
				{"key": "purpose", "label": "For which texts", "kind": "choice", "required": true,
					"options": [
						{"value": "service", "label": "Texts about their work"},
						{"value": "marketing", "label": "Offers and promotions"},
						{"value": "both", "label": "Both, with a separate tick for offers"}
					]},
				{"key": "wording", "label": "The exact words they agree to", "kind": "longtext", "required": true},
				{"key": "link", "label": "Where the networks can see it", "kind": "url", "required": false},
				{"key": "screenshot", "label": "Or a photo or screenshot of it", "kind": "file", "required": false,
					"file_kinds": ["document", "photo"]}
			]},
		{"type": "question", "fact_key": "texting.no_bought_lists", "kind": "yes_no", "required": true,
			"label": "Will you text only people who gave you their number themselves?",
			"hint": "Never bought, rented, shared or copied lists. Texting them can get your number blocked for good."},
		{"type": "question", "fact_key": "texting.stop_help", "kind": "yes_no", "required": true,
			"label": "Do you agree that anyone who replies STOP gets no more texts, and HELP gets your contact details?",
			"hint": "Uplift’s system does this for you automatically."},
		{"type": "question", "fact_key": "texting.privacy_url", "kind": "url", "required": true, "can_defer": true,
			"label": "Where is your privacy policy online?",
			"hint": "It must say you never share customers’ phone numbers for others’ marketing. None yet? Choose that you need Uplift’s help."},
		{"type": "question", "fact_key": "texting.terms_url", "kind": "url", "required": true, "can_defer": true,
			"label": "Where are your texting terms online?",
			"hint": "What texts customers get, how often, that message and data rates may apply, and how to reply STOP or HELP."},
		{"type": "question", "fact_key": "texting.has_opt_out_list", "kind": "yes_no", "required": true,
			"label": "Do you already have a list of people who asked not to be texted?"},
		{"type": "question", "fact_key": "texting.opt_out_list", "kind": "protected_file", "max_files": 5,
			"required": true, "can_defer": true,
			"label": "Upload that list.",
			"hint": "A spreadsheet or document is fine. Uplift makes sure none of them get texts. Only the business owner and Uplift can open it.",
			"show_if": [{"fact_key": "texting.has_opt_out_list", "values": ["yes"]}]}
	]$items$::jsonb
);
