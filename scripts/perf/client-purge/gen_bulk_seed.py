"""Generate bulk background data for the 1M-message purge test (local Docker database only).

Target org c0f2...0001 (the heavy customer's business) gets 2,000 more customers x 500 texts = 1M texts.
Five neighbour orgs get 1,000 customers x 100 texts each, so platform-wide tables are shared like production.
Each text has 2 events and 1 provider callback; every 5th text has a reply. Each customer also has 5 jobs
with 2 assigned visits, 1 file, 1 note and 5 activity rows. Runs as supabase_admin with triggers and FK checks
off (session_replication_role = replica) because rows are generated consistent; the heavy customer itself is
seeded with triggers on by perf_seed.sql.
"""
import sys

OWNER = "c0f10000-0000-0000-0000-000000000001"
ORGS = [("c0f20000-0000-0000-0000-000000000001", 1, 2000, 500)] + [
    (f"c0f20000-0000-0000-0000-00000000000{n}", n, 1000, 100) for n in range(2, 7)
]

out = ["set session_replication_role = replica;", "set statement_timeout = 0;"]
for org, n, clients, texts in ORGS:
    owner = OWNER if n == 1 else f"c0f10000-0000-0000-0000-00000000000{n}"
    c = f"md5('{n}-c-' || g)::uuid"
    cm = f"md5('{n}-cm-' || g)::uuid"
    phone = f"'+1' || (2000000000 + {n} * 10000000 + g)"
    if n != 1:
        out.append(
            f"insert into public.organizations (id, name, slug, lifecycle_status) values "
            f"('{org}', 'Perf Neighbour {n}', 'perf-neighbour-{n}', 'active') on conflict do nothing;"
        )
        out.append(
            "insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, "
            f"created_at, updated_at) values ('{owner}', '00000000-0000-0000-0000-000000000000', 'authenticated', "
            f"'authenticated', 'perf-owner-{n}@example.test', 'test', now(), now(), now()) on conflict do nothing;"
        )
        out.append(
            f"insert into public.organization_members (organization_id, user_id, role) values ('{org}', '{owner}', 'owner');"
        )
    out.append(f"\\echo org {n}")
    out.append(
        f"insert into public.clients (id, organization_id, display_name, first_name, last_name) "
        f"select {c}, '{org}', 'Bulk ' || g, 'Bulk', 'Customer ' || g from generate_series(1, {clients}) g;"
    )
    out.append(
        f"insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary) "
        f"select {cm}, '{org}', {c}, 'phone', {phone}, true from generate_series(1, {clients}) g;"
    )
    out.append("\\echo props")
    out.append(
        "insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code) "
        f"select md5('{n}-p-' || g)::uuid, '{org}', {c}, g || ' Bulk Street', 'Testville', 'TX', '78741' "
        f"from generate_series(1, {clients}) g;"
    )
    # Texts in chunks of 200 customers so each statement stays moderate.
    for start in range(1, clients + 1, 200):
        end = min(start + 199, clients)
        intent = f"md5('{n}-i-' || g || '-' || m)::uuid"
        rng = f"generate_series({start}, {end}) g cross join generate_series(1, {texts}) m"
        out.append(
            "insert into public.communication_delivery_intents (id, organization_id, client_id, "
            "client_contact_method_id, channel, logical_send_key, recipient_phone, status, accepted_at, "
            "provider_message_id) "
            f"select {intent}, '{org}', {c}, {cm}, 'sms', 'bulk-{n}-' || g || '-' || m, {phone}, 'submitted', "
            f"now() - (m || ' hours')::interval, 'SM' || md5('{n}-sm-' || g || '-' || m) from {rng};"
        )
        out.append(
            "insert into public.communication_message_events (organization_id, delivery_intent_id, event_kind) "
            f"select '{org}', {intent}, k from {rng} cross join (values ('queued'), ('sent')) e(k);"
        )
        out.append(
            "insert into public.communication_provider_callback_events (organization_id, delivery_intent_id, "
            "channel, provider, provider_event_key, event_kind, normalized_kind, payload) "
            f"select '{org}', {intent}, 'sms', 'twilio', 'bulk-cb-{n}-' || g || '-' || m, 'delivered', "
            f"'sms_delivered', jsonb_build_object('To', {phone}) from {rng};"
        )
        out.append(
            "insert into public.communication_inbound_messages (organization_id, client_id, "
            "client_contact_method_id, provider, provider_message_id, channel, sender_phone, subject, text_content) "
            f"select '{org}', {c}, {cm}, 'twilio', 'SM' || md5('{n}-in-' || g || '-' || m), 'sms', {phone}, '', "
            f"'Reply ' || m from {rng} where m % 5 = 0;"
        )
        out.append(f"\\echo   texts for customers {start}-{end}")
    job = f"md5('{n}-j-' || g || '-' || j)::uuid"
    out.append(
        "insert into public.jobs (id, organization_id, client_id, property_id, job_number, title, job_type, "
        f"price_basis, currency_code) select {job}, '{org}', {c}, md5('{n}-p-' || g)::uuid, 100000 + (g - 1) * 5 + j, 'Job ' || j, 'one_off', "
        f"'job_total', 'USD' from generate_series(1, {clients}) g cross join generate_series(1, 5) j;"
    )
    out.append(
        "insert into public.job_visits (id, organization_id, job_id, position, visit_date) "
        f"select md5('{n}-v-' || g || '-' || j || '-' || v)::uuid, '{org}', {job}, v, current_date - g % 365 "
        f"from generate_series(1, {clients}) g cross join generate_series(1, 5) j cross join generate_series(0, 1) v;"
    )
    out.append(
        "insert into public.job_visit_assignments (organization_id, visit_id, user_id, job_id) "
        f"select '{org}', visit.id, '{owner}', visit.job_id from public.job_visits visit "
        f"where visit.organization_id = '{org}' and not exists (select 1 from public.job_visit_assignments a "
        "where a.visit_id = visit.id);"
    )
    out.append(
        "insert into public.files (id, organization_id, display_name, mime_type, size_bytes, object_key, "
        "origin_type, origin_id, origin_role, processing_state, scanned_at, checksum_sha256) "
        f"select md5('{n}-f-' || g)::uuid, '{org}', 'photo.jpg', 'image/jpeg', 1000, "
        f"'{org}/files/bulk-' || g || '.jpg', 'client', {c}, 'attachment', 'available', now(), repeat('d', 64) "
        f"from generate_series(1, {clients}) g;"
    )
    out.append(
        "insert into public.file_links (organization_id, file_id, entity_type, entity_id, role) "
        f"select '{org}', md5('{n}-f-' || g)::uuid, 'client', {c}, 'attachment' from generate_series(1, {clients}) g;"
    )
    out.append(
        "insert into public.notes (id, organization_id, body) "
        f"select md5('{n}-n-' || g)::uuid, '{org}', 'Note ' || g from generate_series(1, {clients}) g;"
    )
    out.append(
        "insert into public.note_links (organization_id, note_id, entity_type, entity_id) "
        f"select '{org}', md5('{n}-n-' || g)::uuid, 'client', {c} from generate_series(1, {clients}) g;"
    )
    out.append(
        "insert into public.activity_events (organization_id, entity_type, entity_id, event_type, summary) "
        f"select '{org}', 'client', {c}, 'call', 'Call ' || a from generate_series(1, {clients}) g "
        "cross join generate_series(1, 5) a;"
    )
out.append("set session_replication_role = origin;")
sys.stdout.write("\n".join(out) + "\n")
