-- Client onboarding B4: the approved starter content's stage 2, "Services and service area"
-- (docs/client-onboarding-setup-content-blueprint.md), loaded into the setup draft for Jafar to review and
-- publish. Nothing a client sees changes until he publishes it. The stage is new, so no answer is affected.
--
-- Services are one add-another list, and every later question about them picks from it: the services to
-- promote (in order, the one customers should hire you for first), the ones available urgently. The
-- blueprint's separate "main service" box would have asked for a service twice, so it is the first pick.
-- Service areas work the same way. The real places served are always asked, because Google takes named places
-- only; a distance or travel time is asked in addition when that is how the contractor sets the limit.

select private.setup_load_starter_stage(
	'services',
	'Services and service area',
	'The work you do and where you do it — used on your website, Google profile, quotes and campaigns.',
	null,
	$items$[
		{"type": "heading", "label": "Work offered",
			"hint": "Plain service names are best, the way customers ask for them. Uplift writes the polished wording."},
		{"type": "question", "fact_key": "services.offered", "kind": "list", "max_rows": 20, "required": true,
			"label": "What services do you offer?",
			"hint": "Add each one, starting with the work you most want customers to hire you for.",
			"list_fields": [
				{"key": "name", "label": "Service", "kind": "text", "required": true},
				{"key": "note", "label": "Short note, if useful", "kind": "text", "required": false},
				{"key": "season", "label": "When offered", "kind": "choice", "required": true,
					"options": [
						{"value": "all_year", "label": "All year"},
						{"value": "seasonal", "label": "Only in some seasons"}
					]}
			]},
		{"type": "question", "fact_key": "services.promoted", "kind": "pick", "pick_from": "services.offered",
			"min_choices": 3, "max_choices": 5, "ordered": true, "required": true,
			"label": "Which 3–5 services should Uplift promote first?",
			"hint": "Put the one you most want customers to hire you for at the top."},
		{"type": "question", "fact_key": "services.not_offered", "kind": "list", "max_rows": 10,
			"label": "Is there work customers often ask for that you do not offer?",
			"hint": "Optional. It keeps your website and replies from promising work you turn down.",
			"list_fields": [
				{"key": "name", "label": "Work you don’t do", "kind": "text", "required": true}
			]},
		{"type": "question", "fact_key": "services.customer_type", "kind": "choice", "required": true,
			"label": "Who do you serve?",
			"options": [
				{"value": "residential", "label": "Homeowners and tenants"},
				{"value": "commercial", "label": "Businesses"},
				{"value": "both", "label": "Both"}
			]},
		{"type": "question", "fact_key": "services.urgent", "kind": "yes_no", "required": true,
			"label": "Do you provide emergency or same-day service?"},
		{"type": "question", "fact_key": "services.urgent_services", "kind": "pick",
			"pick_from": "services.offered", "required": true,
			"label": "Which services are available urgently?",
			"show_if": [{"fact_key": "services.urgent", "values": ["yes"]}]},
		{"type": "question", "fact_key": "services.credentials_needed", "kind": "yes_no", "required": true,
			"label": "Do any services need a licence, certification or special warranty?",
			"hint": "For example a gas safety, electrical or roofing licence, or a manufacturer warranty."},
		{"type": "question", "fact_key": "services.credentials", "kind": "list", "max_rows": 10,
			"required": true, "can_defer": true,
			"label": "Add each licence, certification or warranty.",
			"hint": "Add the number only if it may be shown publicly. A copy of the certificate helps but is optional.",
			"show_if": [{"fact_key": "services.credentials_needed", "values": ["yes"]}],
			"list_fields": [
				{"key": "name", "label": "Name", "kind": "text", "required": true},
				{"key": "issuer", "label": "Issued by", "kind": "text", "required": false},
				{"key": "number", "label": "Number, if public", "kind": "text", "required": false},
				{"key": "expires_on", "label": "Expiry date, if any", "kind": "date", "required": false},
				{"key": "file", "label": "Copy of the certificate", "kind": "file", "required": false,
					"file_kinds": ["document", "photo"]}
			]},
		{"type": "question", "fact_key": "services.public_prices", "kind": "yes_no", "required": true,
			"label": "Should any minimum charge or starting price be public?",
			"hint": "Only prices you are happy for customers to see on your website."},
		{"type": "question", "fact_key": "services.prices", "kind": "list", "max_rows": 20, "required": true,
			"label": "Add the prices to show.",
			"hint": "One row per price. Every price is labelled so customers know exactly what it means.",
			"show_if": [{"fact_key": "services.public_prices", "values": ["yes"]}],
			"list_fields": [
				{"key": "service", "label": "Service or charge", "kind": "text", "required": true},
				{"key": "price_type", "label": "Type of price", "kind": "choice", "required": true,
					"options": [
						{"value": "from", "label": "From (starting price)"},
						{"value": "minimum", "label": "Minimum charge"},
						{"value": "fixed", "label": "Fixed price"}
					]},
				{"key": "amount", "label": "Amount", "kind": "money", "required": true},
				{"key": "note", "label": "What it includes, if useful", "kind": "text", "required": false}
			]},

		{"type": "heading", "label": "Area covered",
			"hint": "Where you take work. Real places only — Uplift never lists places you don’t serve."},
		{"type": "question", "fact_key": "area.base_city", "kind": "reuse", "reuse_from": "business.address_city",
			"required": true, "label": "What town or city is the business based in?"},
		{"type": "question", "fact_key": "area.limit_type", "kind": "choice", "required": true,
			"label": "How do you decide whether a job is too far?",
			"options": [
				{"value": "places", "label": "Only the places I list"},
				{"value": "distance", "label": "A distance from my base"},
				{"value": "travel_time", "label": "A travel time from my base"}
			]},
		{"type": "question", "fact_key": "area.places", "kind": "list", "max_rows": 50, "required": true,
			"can_defer": true,
			"label": "Which towns, cities, postcodes, counties or regions do you serve?",
			"hint": "Google lists service areas by place name, so add the places even if you also go by distance.",
			"list_fields": [
				{"key": "name", "label": "Place", "kind": "text", "required": true}
			]},
		{"type": "question", "fact_key": "area.max_distance", "kind": "distance", "required": true,
			"label": "What is the furthest you normally travel?",
			"show_if": [{"fact_key": "area.limit_type", "values": ["distance"]}]},
		{"type": "question", "fact_key": "area.max_travel_time", "kind": "duration", "required": true,
			"label": "What is the longest you normally travel to a job?",
			"show_if": [{"fact_key": "area.limit_type", "values": ["travel_time"]}]},
		{"type": "question", "fact_key": "area.excluded", "kind": "list", "max_rows": 20,
			"label": "Are there areas inside that boundary you do not serve?",
			"hint": "Optional. For example an island, a city centre with no parking, or a neighbouring town.",
			"list_fields": [
				{"key": "name", "label": "Place", "kind": "text", "required": true}
			]},
		{"type": "question", "fact_key": "area.promoted", "kind": "pick", "pick_from": "area.places",
			"max_choices": 5, "ordered": true, "required": true,
			"label": "Which places should Uplift promote first?",
			"hint": "Up to 5, most important first. Your website and campaigns lead with these."},
		{"type": "question", "fact_key": "area.other_locations", "kind": "yes_no", "required": true,
			"label": "Do you have another permanently staffed location?",
			"hint": "A second office, yard or showroom with staff. A temporary job site does not count."},
		{"type": "question", "fact_key": "area.locations", "kind": "list", "max_rows": 5, "required": true,
			"can_defer": true, "label": "Add each staffed location.",
			"show_if": [{"fact_key": "area.other_locations", "values": ["yes"]}],
			"list_fields": [
				{"key": "address", "label": "Address", "kind": "text", "required": true},
				{"key": "phone", "label": "Phone", "kind": "phone", "required": false},
				{"key": "hours", "label": "Opening hours", "kind": "text", "required": false},
				{"key": "services", "label": "Services offered there", "kind": "text", "required": false},
				{"key": "customers_visit", "label": "Do customers visit?", "kind": "yes_no", "required": true}
			]}
	]$items$::jsonb
);
