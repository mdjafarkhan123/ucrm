-- Client onboarding B8: the approved starter content's stage 8, "Calls and routing"
-- (docs/client-onboarding-setup-content-blueprint.md), loaded into the setup draft for Jafar to review and
-- publish. Nothing a client sees changes until he publishes it. The stage is new, so no answer is affected, and
-- it is shown only to a client whose package includes Calls and texting.
--
-- Only number choices that work in the client's country are offered. Every country can get a new number,
-- forward calls, or ask to move a number (Uplift checks the country and phone company first). Texting from a
-- number whose calls stay with another company works only for US and Canadian landline and toll-free numbers
-- (Twilio's Hosted SMS), so that question is asked only there.
--
-- A recent bill, a transfer PIN and the signed transfer letter are never ordinary answers: B9's protected
-- documents collect them. Texting rules such as quiet hours belong to stage 9. Choosing a missed-call text
-- here never switches texting on before registration.

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
			"hint": "Your phone company has to agree, and the details must match its records exactly. Keep your current phone service until the move is finished. Uplift asks for a recent bill and any transfer PIN separately, in a protected step."},
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
