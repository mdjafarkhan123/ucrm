# Brevo transactional webhook retries forever on an unknown delivery_intent_id

The `/api/webhooks/brevo/transactional` route inserts the callback event with the `delivery_intent_id`
parsed from the `ucrm:email:<id>` tag. If that intent id is not in `communication_delivery_intents`, the
insert fails FK constraint `communication_provider_callback_events_delivery_intent_id_fkey` (23503) and the
route asks Brevo to retry — so Brevo retries that event indefinitely.

Observed 2026-08-29 from a manual test send that used a throwaway intent id (not a real delivery intent).
Normal outbound always has a real intent row, so this does not fire in the normal flow — but a stray/deleted
intent, or any Brevo event for mail sent outside the outbox, triggers a retry storm and error-log noise.

**Reactivate when:** touching the Brevo transactional webhook, or investigating webhook retry storms / repeated
23503 log lines.

**Known constraint:** the fix is to ACK (2xx) and skip an event whose delivery_intent_id is unknown, instead
of asking for a retry — do not start recording callbacks against a non-existent intent.
