-- Client onboarding B11: the approved starter content's stages 4 and 5, "How your CRM should work" and "Move
-- your existing data" (docs/client-onboarding-setup-content-blueprint.md), loaded into the setup draft for Jafar
-- to review and publish. Nothing a client sees changes until he publishes it. Both stages are new, so no answer
-- is affected, and both are shown to everyone.
--
-- Questions are everyday situations, not CRM words. Uplift's recommended answer is marked "(recommended)" for the
-- client to confirm or change. Nothing here sends, imports, charges or makes a tax or legal claim: the two
-- recommended customer emails are only prepared, and wait for a verified sender and the client's final look.
--
-- Facts given in earlier stages are confirmed, not typed again: who hears about new enquiries (the website
-- form's people) and how customers pay. A client not asked one of those is asked it here instead. A question
-- can only reuse an earlier one, so these stages come after the service stages rather than fourth and fifth as
-- the blueprint lists them. The working hours are built in so they can use the weekly-hours control; the setup
-- page fills them in from the customer-facing hours for the client to confirm.
--
-- Importing is a request, never an action: files are protected (they hold customers' details), and Uplift shows
-- a preview for approval before anything goes in. Choosing "start fresh" never blocks setup.

select private.setup_load_starter_stage(
	'crm',
	'How your CRM should work',
	'How a new enquiry becomes booked, paid work in your business. Uplift’s recommended answers are marked — keep them or change them.',
	null,
	$items$[
		{"type": "heading", "label": "From enquiry to booked work",
			"hint": "What happens after someone gets in touch. Every new enquiry lands in your CRM as a request for you to look at — nothing is booked for you."},
		{"type": "question", "fact_key": "crm.enquiry_path", "kind": "choice", "required": true,
			"label": "What normally happens after a new customer contacts you?",
			"options": [
				{"value": "review", "label": "I look at it first, then decide on a visit, a quote or the work (recommended)"},
				{"value": "visit_first", "label": "I visit before I quote"},
				{"value": "quote_from_details", "label": "I quote from their details and photos"},
				{"value": "book_directly", "label": "I book the work straight away"},
				{"value": "varies", "label": "It depends on the job"}
			]},
		{"type": "question", "fact_key": "crm.assessment_when", "kind": "longtext", "max_length": 1000,
			"label": "Which enquiries need a visit before you can quote?",
			"hint": "Optional. For example: anything over one room, or every roof job.",
			"show_if": [{"fact_key": "crm.enquiry_path", "values": ["review", "visit_first", "quote_from_details", "varies"]}]},
		{"type": "question", "fact_key": "crm.enquiry_recipients", "kind": "reuse", "reuse_from": "website.form_recipients",
			"required": true,
			"label": "Who should hear about new enquiries first?",
			"hint": "Usually you or your office."},
		{"type": "question", "fact_key": "crm.enquiry_owner", "kind": "choice", "required": true,
			"label": "Who looks after a new enquiry until it is booked or closed?",
			"hint": "One person, so nothing falls between two people. You can change it on any enquiry later.",
			"options": [
				{"value": "main_contact", "label": "The main contact named in Your business"},
				{"value": "someone_else", "label": "Someone else"}
			]},
		{"type": "question", "fact_key": "crm.enquiry_owner_person", "kind": "list", "max_rows": 1, "required": true,
			"label": "Who looks after new enquiries?",
			"show_if": [{"fact_key": "crm.enquiry_owner", "values": ["someone_else"]}],
			"list_fields": [
				{"key": "name", "label": "Name", "kind": "text", "required": true},
				{"key": "email", "label": "Email", "kind": "email", "required": false}
			]},
		{"type": "question", "fact_key": "crm.quote_needs", "kind": "multi_choice", "required": true,
			"allow_other": true,
			"label": "What must a customer tell you before you can quote?",
			"hint": "Your enquiry form and request asks for these.",
			"options": [
				{"value": "address", "label": "The address of the work"},
				{"value": "photos", "label": "Photos"},
				{"value": "measurements", "label": "Measurements or sizes"},
				{"value": "urgency", "label": "How soon they need it"},
				{"value": "budget", "label": "Their budget"},
				{"value": "access", "label": "Access details, like parking or gate codes"}
			]},
		{"type": "question", "fact_key": "crm.reply_target", "kind": "choice", "required": true,
			"label": "How quickly do you aim to reply to a new enquiry?",
			"hint": "Your own target, so the CRM can flag enquiries waiting too long. Customers never see it.",
			"options": [
				{"value": "15_minutes", "label": "Within 15 minutes"},
				{"value": "1_hour", "label": "Within an hour"},
				{"value": "same_day", "label": "The same working day"},
				{"value": "next_day", "label": "By the next working day"}
			]},
		{"type": "question", "fact_key": "crm.teams", "kind": "choice", "required": true,
			"label": "Does one team handle all the work?",
			"options": [
				{"value": "one", "label": "Yes, one team does everything (most businesses)"},
				{"value": "separate", "label": "No, we have separate trades, branches or departments"}
			]},
		{"type": "question", "fact_key": "crm.team_units", "kind": "list", "max_rows": 10, "required": true,
			"can_defer": true,
			"label": "Add each separate team and what it handles.",
			"hint": "Only teams that really work separately — for example “Plumbing” and “Heating”, or two branches.",
			"show_if": [{"fact_key": "crm.teams", "values": ["separate"]}],
			"list_fields": [
				{"key": "name", "label": "Team, branch or department", "kind": "text", "required": true},
				{"key": "handles", "label": "What it handles", "kind": "text", "required": true}
			]},

		{"type": "heading", "label": "Quotes, jobs and scheduling",
			"hint": "How you price and book the work. Uplift sets these up as your starting settings."},
		{"type": "question", "fact_key": "crm.quote_valid_days", "kind": "number", "required": true,
			"label": "For how many days should a quote stay valid?",
			"hint": "Uplift recommends 30 days. After that, the customer asks you to check the price again."},
		{"type": "question", "fact_key": "crm.quote_approval", "kind": "yes_no", "required": true,
			"label": "Should customers approve a quote before the work is booked?",
			"hint": "Uplift recommends Yes: the customer approves online, so you both have a record of what was agreed."},
		{"type": "question", "fact_key": "crm.deposit", "kind": "choice", "required": true,
			"label": "Do you normally take a deposit?",
			"hint": "Nothing is charged automatically — this only sets what a new quote asks for.",
			"options": [
				{"value": "never", "label": "No"},
				{"value": "always", "label": "Yes, on every job"},
				{"value": "some", "label": "Only for some work"}
			]},
		{"type": "question", "fact_key": "crm.deposit_type", "kind": "choice", "required": true, "can_defer": true,
			"label": "How is the deposit worked out?",
			"show_if": [{"fact_key": "crm.deposit", "values": ["always", "some"]}],
			"options": [
				{"value": "percentage", "label": "A percentage of the quote"},
				{"value": "fixed", "label": "A fixed amount"}
			]},
		{"type": "question", "fact_key": "crm.deposit_percentage", "kind": "percentage", "required": true,
			"label": "What percentage?",
			"show_if": [{"fact_key": "crm.deposit_type", "values": ["percentage"]}]},
		{"type": "question", "fact_key": "crm.deposit_amount", "kind": "money", "required": true,
			"label": "What amount?",
			"show_if": [{"fact_key": "crm.deposit_type", "values": ["fixed"]}]},
		{"type": "question", "fact_key": "crm.deposit_note", "kind": "longtext", "max_length": 500,
			"required": true, "can_defer": true,
			"label": "Which work needs a deposit?",
			"hint": "For example: jobs over 2,000, or anything where you order materials.",
			"show_if": [{"fact_key": "crm.deposit", "values": ["some"]}]},
		{"type": "question", "fact_key": "crm.quote_terms", "kind": "longtext", "max_length": 2000,
			"required": true, "can_defer": true,
			"label": "What terms should customers see on your quotes?",
			"hint": "Paste the wording you use now. Uplift can tidy the layout but never writes legal terms for you."},
		{"type": "question", "fact_key": "crm.quote_terms_file", "kind": "file", "file_kinds": ["document"],
			"max_files": 1,
			"label": "Or upload the document with your terms.",
			"hint": "Optional."},
		{"type": "question", "fact_key": "crm.work_hours", "built_in": true, "required": true,
			"label": "When can work normally be booked in?",
			"hint": "This can be different from when customers can reach you — for example, crews may start before the phones open."},
		{"type": "question", "fact_key": "crm.notice", "kind": "choice", "allow_other": true,
			"label": "How much notice do you normally need before a job?",
			"hint": "Optional.",
			"options": [
				{"value": "same_day", "label": "Same day is fine"},
				{"value": "next_day", "label": "At least a day"},
				{"value": "few_days", "label": "A few days"},
				{"value": "week", "label": "A week or more"}
			]},
		{"type": "question", "fact_key": "crm.travel_buffer", "kind": "duration",
			"label": "How much travel or setup time should be left between visits?",
			"hint": "Optional. Leave it empty if it varies too much to say."},
		{"type": "question", "fact_key": "crm.visit_types", "kind": "list", "max_rows": 10, "required": true,
			"can_defer": true,
			"label": "Which kinds of visit should be ready on day one?",
			"hint": "For example “Free estimate visit, 1 hour” or “Boiler service, half a day”. If you’re not sure, Uplift starts you with an estimate visit and a standard job.",
			"list_fields": [
				{"key": "name", "label": "Name", "kind": "text", "required": true},
				{"key": "length", "label": "How long it usually takes", "kind": "text", "required": true},
				{"key": "arrival", "label": "Arrival time given to the customer", "kind": "choice", "required": true,
					"options": [
						{"value": "exact", "label": "An exact time"},
						{"value": "1_hour", "label": "A 1-hour window"},
						{"value": "2_hours", "label": "A 2-hour window"},
						{"value": "4_hours", "label": "Morning or afternoon"},
						{"value": "all_day", "label": "Sometime that day"}
					]},
				{"key": "purpose", "label": "What it is for", "kind": "choice", "required": true,
					"options": [
						{"value": "assessment", "label": "A visit to look and quote"},
						{"value": "job", "label": "Doing the work"}
					]}
			]},
		{"type": "question", "fact_key": "crm.pricing", "kind": "choice", "required": true,
			"label": "How do you normally price your work?",
			"options": [
				{"value": "fixed", "label": "A fixed price for each service"},
				{"value": "hourly", "label": "By the hour or day"},
				{"value": "per_unit", "label": "Per unit, like per square metre or per window"},
				{"value": "custom", "label": "A custom quote for every job"},
				{"value": "mix", "label": "A mix of these"}
			]},
		{"type": "question", "fact_key": "crm.pricing_note", "kind": "text", "max_length": 300,
			"label": "Anything Uplift should know about your pricing?",
			"hint": "Optional. For example: a call-out charge, or a minimum job price."},
		{"type": "question", "fact_key": "crm.price_list", "kind": "yes_no_unsure", "required": true,
			"label": "Do you already have a list of your services and prices?",
			"hint": "If you do, send it under Move your existing data — no need to type it in here."},

		{"type": "heading", "label": "Invoices, tax and payment",
			"hint": "How you ask to be paid. Nothing about tax is assumed — your invoices show only what you confirm here."},
		{"type": "question", "fact_key": "crm.invoice_due", "kind": "choice", "required": true,
			"label": "When are your invoices normally due?",
			"options": [
				{"value": "recommended", "label": "Homeowners on receipt, business customers in 30 days (recommended)"},
				{"value": "on_receipt", "label": "On receipt, for everyone"},
				{"value": "before_work", "label": "Before the work starts"},
				{"value": "on_completion", "label": "When the work is finished"},
				{"value": "days", "label": "A set number of days after the invoice"}
			]},
		{"type": "question", "fact_key": "crm.invoice_due_days", "kind": "number", "required": true,
			"label": "How many days after the invoice?",
			"show_if": [{"fact_key": "crm.invoice_due", "values": ["days"]}]},
		{"type": "question", "fact_key": "crm.tax", "kind": "choice", "required": true, "can_defer": true,
			"label": "How do you handle tax on your prices?",
			"hint": "For example VAT, GST or sales tax. If you’re not sure, choose “I need Uplift’s help” and Uplift checks it with you.",
			"options": [
				{"value": "included", "label": "Tax is included in my prices"},
				{"value": "added", "label": "Tax is added on top of my prices"},
				{"value": "not_registered", "label": "I’m not registered, so I don’t charge tax"},
				{"value": "varies", "label": "It depends on the job or customer"}
			]},
		{"type": "question", "fact_key": "crm.tax_numbers", "kind": "list", "max_rows": 3, "required": true,
			"can_defer": true,
			"label": "Which tax name and registration number go on your invoices?",
			"hint": "For example “VAT” and your VAT number, “GST/HST” and your business number, “ABN” in Australia, or your sales tax permit in the US.",
			"show_if": [{"fact_key": "crm.tax", "values": ["included", "added", "varies"]}],
			"list_fields": [
				{"key": "name", "label": "Tax name", "kind": "text", "required": true},
				{"key": "number", "label": "Registration number", "kind": "text", "required": true}
			]},
		{"type": "question", "fact_key": "crm.payment_methods", "kind": "reuse", "reuse_from": "proof.payment_methods",
			"required": true,
			"label": "Which ways to pay should your invoices mention?"},
		{"type": "question", "fact_key": "crm.payment_instructions", "kind": "longtext", "max_length": 1000,
			"required": true, "can_defer": true,
			"label": "What payment instructions should customers get?",
			"hint": "For example the bank details for a transfer, or who to make a cheque out to. Uplift never needs your banking password."},
		{"type": "question", "fact_key": "crm.invoice_terms", "kind": "longtext", "max_length": 2000,
			"label": "Any invoice terms or late-payment wording you use?",
			"hint": "Optional. Paste your own wording — Uplift never adds fees or legal terms you haven’t given."},

		{"type": "heading", "label": "Your team",
			"hint": "Who uses the CRM with you. Nobody is invited yet — Uplift checks the list with you first."},
		{"type": "question", "fact_key": "crm.team_members", "kind": "list", "max_rows": 20,
			"label": "Who else needs to use the CRM when you start?",
			"hint": "Optional. You can add people later in Settings.",
			"list_fields": [
				{"key": "name", "label": "Name", "kind": "text", "required": true},
				{"key": "email", "label": "Work email", "kind": "email", "required": true},
				{"key": "role", "label": "What they do", "kind": "choice", "required": true,
					"options": [
						{"value": "admin", "label": "Helps run the whole business"},
						{"value": "office", "label": "Office — customers and the schedule"},
						{"value": "sales", "label": "Sales — enquiries and quotes"},
						{"value": "finance", "label": "Finance — invoices and payments"},
						{"value": "field", "label": "Field — does the work on site"}
					]},
				{"key": "note", "label": "Anything else about their job", "kind": "text", "required": false}
			]},
		{"type": "question", "fact_key": "crm.alert_people", "kind": "pick", "pick_from": "crm.team_members",
			"label": "Who should get alerts about urgent enquiries or schedule changes?",
			"hint": "Optional. You and the people above."},
		{"type": "question", "fact_key": "crm.office_field_note", "kind": "longtext", "max_length": 1000,
			"label": "Anything Uplift should know about how office and field work is split?",
			"hint": "Optional. For example: “Field staff shouldn’t see prices.”"},

		{"type": "heading", "label": "Recommended customer messages",
			"hint": "Uplift can prepare these for you. Nothing is sent until your email is verified and you have read the final wording."},
		{"type": "question", "fact_key": "crm.quote_followups", "kind": "yes_no", "required": true,
			"label": "Should Uplift prepare two follow-up emails for quotes customers haven’t answered?",
			"hint": "Uplift recommends Yes. They go 3 and 7 days after the quote arrives, and stop as soon as the customer replies or the quote is answered."},
		{"type": "question", "fact_key": "crm.quick_reply", "kind": "yes_no", "required": true,
			"label": "Should Uplift prepare a quick reply for website enquiries?",
			"hint": "Uplift recommends Yes. If nobody has replied within five minutes, the customer gets your approved thank-you email. Texts need Calls and texting, set up and registered.",
			"show_if": [{"service_key": "website"}]},
		{"type": "question", "fact_key": "crm.message_approver", "kind": "choice", "required": true,
			"label": "Who approves customer messages before they start?",
			"hint": "This person sees the exact wording before anything goes to a customer.",
			"options": [
				{"value": "final_approver", "label": "The person giving final approval in Your business (recommended)"},
				{"value": "someone_else", "label": "Someone else"}
			]},
		{"type": "question", "fact_key": "crm.message_approver_person", "kind": "list", "max_rows": 1, "required": true,
			"label": "Who approves customer messages?",
			"show_if": [{"fact_key": "crm.message_approver", "values": ["someone_else"]}],
			"list_fields": [
				{"key": "name", "label": "Name", "kind": "text", "required": true},
				{"key": "email", "label": "Email", "kind": "email", "required": true}
			]}
	]$items$::jsonb
);

select private.setup_load_starter_stage(
	'import',
	'Move your existing data',
	'Bring your customers, prices and money owed over from what you use now — or start fresh.',
	null,
	$items$[
		{"type": "heading", "label": "What to bring over",
			"hint": "Uplift brings your data in for you. You see a preview of everything first, and nothing goes in until you approve it."},
		{"type": "question", "fact_key": "import.wanted", "kind": "choice", "required": true,
			"label": "Do you want to bring existing business data into Uplift?",
			"options": [
				{"value": "yes", "label": "Yes"},
				{"value": "no", "label": "No, I’ll start fresh"},
				{"value": "not_sure", "label": "I’m not sure yet"},
				{"value": "help", "label": "I’d like Uplift to help me decide"}
			]},
		{"type": "question", "fact_key": "import.source", "kind": "choice", "allow_other": true,
			"required": true, "can_defer": true,
			"label": "Where is your data today?",
			"show_if": [{"fact_key": "import.wanted", "values": ["yes", "not_sure"]}],
			"options": [
				{"value": "other_crm", "label": "Another CRM or job app"},
				{"value": "accounting", "label": "Accounting software"},
				{"value": "spreadsheets", "label": "Spreadsheets"},
				{"value": "phone", "label": "My phone’s contacts"},
				{"value": "paper", "label": "On paper"},
				{"value": "mixed", "label": "A mix of these"}
			]},
		{"type": "question", "fact_key": "import.what", "kind": "multi_choice", "required": true,
			"label": "What would you like to bring over?",
			"hint": "Each one gets its own preview.",
			"show_if": [{"fact_key": "import.wanted", "values": ["yes", "not_sure"]}],
			"options": [
				{"value": "customers", "label": "Customers and their addresses"},
				{"value": "services", "label": "Services and prices"},
				{"value": "balances", "label": "Money customers already owe you"}
			]},
		{"type": "question", "fact_key": "import.count", "kind": "choice",
			"label": "Roughly how many customers or records are there?",
			"hint": "Optional — a guess is fine.",
			"show_if": [{"fact_key": "import.wanted", "values": ["yes", "not_sure"]}],
			"options": [
				{"value": "under_100", "label": "Fewer than 100"},
				{"value": "100_1000", "label": "100 to 1,000"},
				{"value": "1001_5000", "label": "1,001 to 5,000"},
				{"value": "more", "label": "More, or I don’t know"}
			]},

		{"type": "heading", "label": "Your files",
			"hint": "Only the business owner and Uplift can open these. Uplift never asks for the password to your old system."},
		{"type": "question", "fact_key": "import.files", "kind": "protected_file", "max_files": 10,
			"required": true, "can_defer": true,
			"label": "Upload the cleanest export or spreadsheet you have.",
			"hint": "Most apps have an “Export” or “Download” button that gives a spreadsheet. Photos of paper records work too. If you’re stuck, choose “I need Uplift’s help” and Uplift sends a simple template.",
			"show_if": [{"fact_key": "import.wanted", "values": ["yes", "not_sure"]}]},
		{"type": "question", "fact_key": "import.messy", "kind": "yes_no_unsure", "required": true,
			"label": "Is any of it handwritten, scanned, damaged, or full of duplicates?",
			"hint": "That’s fine — it just means Uplift looks at it more closely first.",
			"show_if": [{"fact_key": "import.wanted", "values": ["yes", "not_sure"]}]},

		{"type": "heading", "label": "Before anything goes in",
			"hint": "Uplift shows how many rows are ready, which have problems and which look like duplicates — then waits for a yes."},
		{"type": "question", "fact_key": "import.approver", "kind": "choice", "required": true,
			"label": "Who approves the preview before anything is brought in?",
			"show_if": [{"fact_key": "import.wanted", "values": ["yes", "not_sure"]}],
			"options": [
				{"value": "final_approver", "label": "The person giving final approval in Your business (recommended)"},
				{"value": "someone_else", "label": "Someone else"}
			]},
		{"type": "question", "fact_key": "import.approver_person", "kind": "list", "max_rows": 1, "required": true,
			"label": "Who approves the preview?",
			"show_if": [{"fact_key": "import.approver", "values": ["someone_else"]}],
			"list_fields": [
				{"key": "name", "label": "Name", "kind": "text", "required": true},
				{"key": "email", "label": "Email", "kind": "email", "required": true}
			]},
		{"type": "question", "fact_key": "import.nothing_sent", "kind": "yes_no", "required": true,
			"label": "Do you agree that bringing data in must never send anything to your customers?",
			"hint": "No messages, reminders, invoices or automations go out because of an import — Uplift keeps them all off while your data comes in.",
			"show_if": [{"fact_key": "import.wanted", "values": ["yes", "not_sure"]}]}
	]$items$::jsonb
);
